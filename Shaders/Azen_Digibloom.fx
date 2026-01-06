//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2024
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Zentient: Radon v0.1 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#if(__RENDERER__ != 0x9000)

	#include "ReShade.fxh"
	#include "ZenteonCommon.fxh"
	
	
	#ifndef PERFORMANCE_MODE
	//============================================================================================
		#define PERFORMANCE_MODE 1
	//============================================================================================
	#endif
	
	//Pixel Preprocessor helpers
	#define PS_DOWNSAMPLE_OUTPUTS out float4 Lum : SV_Target0, out precise float2 Dep : SV_Target1, out float2 Nor : SV_Target2
	
	#define DISPATCH_X(Y, DIS_RES_DIV) DispatchSizeX = 1; DispatchSizeY = DIV_RND_UP(RES.y, Y * DIS_RES_DIV)
	#define DISPATCH_Y(X, DIS_RES_DIV) DispatchSizeX = DIV_RND_UP(RES.x, X * DIS_RES_DIV); DispatchSizeY = 1
	
	//Misc helpers
	#define BackBuffer ReShade::BackBuffer
	
	#define DISR_RES_DIV (1 + PERFORMANCE_MODE)
	#define R_RES (RES / DISR_RES_DIV)
	
	uniform int BLOOM_PRESET <
		ui_type = "combo";
		ui_label = "Bloom Preset";
		ui_items = "Digi\0Hoyo\0Clear\0Smear\0";
	> = 0;
	
	uniform float BLOOM_INTENSITY <
		ui_type = "drag";
		ui_label = "Bloom Intensity";
		ui_min = 0.0;
		ui_max = 1.0;
	> = 0.5;
	
	uniform float BLOOM_RADIUS <
		ui_type = "drag";
		ui_label = "Bloom Radius";
		ui_min = 0.1;
		ui_max = 1.0;
	> = 0.5;
	
	namespace Digibloom {
		
		texture2D tHDR { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sHDR { Texture = tHDR; WRAPMODE(BORDER); };
		
		//Hate to be this careless with memory, 
		//but significantly reduces the pass overhead to accumulate between passes
		
		texture2D tTemp0 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sTemp0 { Texture = tTemp0; };
		storage2D cTemp0 { Texture = tTemp0; MipLevel = 0; };
		
		texture2D tTemp1 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sTemp1 { Texture = tTemp1; };
		storage2D cTemp1 { Texture = tTemp1; MipLevel = 0; };
		
		texture2D tTemp2 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sTemp2 { Texture = tTemp2; };
		storage2D cTemp2 { Texture = tTemp2; MipLevel = 0; };
		
		texture2D tTemp3 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sTemp3 { Texture = tTemp3; };
		storage2D cTemp3 { Texture = tTemp3; MipLevel = 0; };
		
		texture2D tAcc0 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sAcc0 { Texture = tAcc0; };
		
		texture2D tAcc1 { DIVRES(DISR_RES_DIV); Format = RGBA16F; };
		sampler2D sAcc1 { Texture = tAcc1; };
		
		//Turning bugs into features, exp decay kernel is definitely not seperable
		void SweepX(int sX, int2 id, sampler2D sI, storage2D cO, float2 vec)
		{
			id.x = sX;
			float4 emo = 0.0;
			float4 emo2 = emo;
			vec = normalize(vec);
			float2 slope = vec / abs(vec.x);
			
			for(int i; i <= R_RES.x; i++)
			{
				int2 tid = id.xy + (slope * i);
				float4 samp = tex2Dfetch(sI, tid);//tex2Dlod(sI, float4(tid / R_RES, 0, 0) );
				
				emo = lerp(emo, samp,  rcp(0.15 * R_RES.y * BLOOM_RADIUS) );
				emo2 = lerp(emo2, samp,  rcp(0.03 * R_RES.y * BLOOM_RADIUS) );
				tex2Dstore(cO, tid, 0.5 * (emo2 + emo));
			}
		}
		
		//Faster
		void SweepY(int sY, int2 id, sampler2D sI, storage2D cO, float2 vec)
		{
			id.y = sY;
			float4 emo = 0.0;
			float4 emo2 = emo;
			vec = normalize(vec);
			float2 slope = vec / abs(vec.y);
			
			for(int i; i <= R_RES.y; i++)
			{
				int2 tid = id.xy + (slope * i);
				float4 samp = tex2Dfetch(sI, tid);//tex2Dlod(sI, float4(tid / R_RES, 0, 0) );
				
				emo = lerp(emo, samp, rcp(0.15 * R_RES.y * BLOOM_RADIUS) );
				emo2 = lerp(emo2, samp,  rcp(0.03 * R_RES.y * BLOOM_RADIUS) );
				tex2Dstore(cO, tid, 0.5 * (emo2 + emo) );
			}
		}
		
		float3 TMO(float3 x)
		{
			return pow(1.05 * x / (x + 1.0), rcp(2.2));
		}
		
		float3 ITMO(float3 x)
		{
			x = pow(x,2.2);
			return max(0, -x / (x - 1.05));
		}
		
		//===================================================================================
		//Prep passes
		//===================================================================================
		float4 GenHDRPS(PS_INPUTS) :SV_Target
		{
			float3 i = GetBackBuffer(xy + 0.5 / RES);
			float il = GetLuminance(i);
			float d  = GetDepth(xy);
			return float4(ITMO(i), d);
		}
		
		//===================================================================================
		//Blur passes
		//===================================================================================
		
		[shader("compute")]
		void Blur0CS(CS_INPUTS)
		{
			if(id.y == 1) { SweepY(0, id.xy, sHDR, cTemp0, float2(0, 1) ); }
			else { id.y = 1; SweepY(R_RES.y, id.xy, sHDR, cTemp1, float2(0, -1) ); }
		}
		
		[shader("compute")]
		void Blur1CS(CS_INPUTS)
		{
			if(id.x == 1) { SweepX(0, id.xy, sAcc0, cTemp2, float2(1, 0) ); }
			else { id.x = 1; SweepX(R_RES.x, id.xy, sAcc0, cTemp3, float2(-1, 0) ); }
		}
		
		
		//===================================================================================
		//Accumulate passes
		//===================================================================================
		
		[shader("pixel")]
		float4 AccPS0(PS_INPUTS) : SV_Target
		{
			float2 hp = 0.0 / R_RES;
			return tex2D(sTemp0, xy + hp) + tex2D(sTemp1, xy + hp);
		}
		
		[shader("pixel")]
		float4 AccPS1(PS_INPUTS) : SV_Target
		{
			float2 hp = 0.0 / R_RES;
			return tex2D(sTemp2, xy + hp) + tex2D(sTemp3, xy + hp);
		}
		
		//===================================================================================
		//Blending passes
		//===================================================================================
		
		float3 SoftLight(float3 a, float3 b)
		{
			return (1.0-2.0*a) * b*b + 2.0*b*a;
		}
		
		float3 Screen(float3 a, float3 b)
		{
			return 1.0 - (1-a)*(1-b);
		}
		
		float3 SoftScreen(float3 a, float3 b)
		{
			float3 l = (1.0-2.0*a) * b*b + 2.0*b*a;
			float3 s = 1.0 - (1.0 - l) * (1.0 - a);
			return 0.5*(l+s);
		}
		
		float3 HardLight(float3 a, float3 b)
		{
			return b > 0.5 ? 1.0 - 2.0*(1.0-a)*(1.0-b) : 2.0*a*b;
		}
		
		
		[shader("pixel")]
		float3 BlendPS(PS_INPUTS) : SV_Target
		{
			float4 t = tex2D(sAcc1, xy) / 4.0;
			float3 bloom = t.rgb;
			float3 input = ITMO(GetBackBuffer(xy));
			
			float d = GetDepth(xy);
			float mask = saturate(t.a/d) * saturate(d/t.a);
			
			mask *= mask;
			mask = smoothstep(0,1,mask);
			//mask *= mask;
			//mask = 0.5 + 0.3 * (0.5-mask) / (abs(0.5-mask) - 0.8);//			..mask *= mask;
			
			bloom = TMO(bloom);
			input = TMO(input);
			
			switch(BLOOM_PRESET) {
				case 0:
					return lerp(input, SoftScreen(input, bloom), 0.67 * BLOOM_INTENSITY);
				case 1:
					return lerp(input, SoftScreen(input, bloom), mask * float3(0.8,0.3,0.25) * BLOOM_INTENSITY);
				case 2:
					return TMO(lerp(ITMO(input), ITMO(bloom*bloom), 0.25 * BLOOM_INTENSITY));
				case 3:
					return TMO(lerp(ITMO(input), ITMO(bloom), 0.25 * BLOOM_INTENSITY));
			}
			return 0;
			
		}
		
		technique AzenDigiBloom <
		ui_label = "Azen: Digibloom";
		    ui_tooltip =        
		        "Azen - Digibloom           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nDigibloom is a bloom shader that attempts to replicate digital art processes instead of cameras"
		        "\n"
		        "\n=================================================================================================";
		>	
		{
			pass { VertexShader = PostProcessVS; PixelShader = GenHDRPS; RenderTarget = tHDR; }
		
			//No improvements on my end above 8, 32 is theoretically optimal for most GPUs iirc though
			#define DISP_TDS 32
			
			pass sweep0 { ComputeShader = Blur0CS<DISP_TDS,2>; DISPATCH_Y(DISP_TDS, DISR_RES_DIV); }
			pass { VertexShader = PostProcessVS; PixelShader = AccPS0; RenderTarget = tAcc0; }
			
			pass sweep1 { ComputeShader = Blur1CS<2, DISP_TDS>; DISPATCH_X(DISP_TDS, DISR_RES_DIV); }
			pass { VertexShader = PostProcessVS; PixelShader = AccPS1; RenderTarget = tAcc1; }
			
			
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = BlendPS;
			}
		}
	}
	
#else	
	int Dx9Warning <
		ui_type = "radio";
		ui_text = "Oops, looks like you're using DX9\n"
			"Digibloom requires compute shader support, if you'd like to use it in older games try using a wrapper like DXVK";
		ui_label = " ";
		> = 0;
		
	technique AzenDigiBloom <
		ui_label = "Azen: Digibloom";
		    ui_tooltip =        
		        "Azen - Digibloom           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nDigibloom is a bloom shader that attempts to replicate digital art processes instead of cameras"
		        "\n"
		        "\n=================================================================================================";
		>	
	{}
#endif	
	
