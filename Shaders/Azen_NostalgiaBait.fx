//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2026
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Azen - Nostalgia Bait - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "AzenCommon.fxh"

	
uniform int FRAME_COUNT <
	source = "framecount";>;

uniform int DESCRIPTION <
	ui_label = " ";
	ui_category = "NostalgiaBait";
	ui_type = "radio";
	ui_text = "NostalgiaBait is a relatively simple shader meant to emulate 'the look' of cheap \n"
			  "digital cameras from the early 2000s-2010s \n"
			  "100% human code, with color transforms captured from physical cameras.\n";
> = 0;

uniform float INPUT_WP <
	ui_type = "drag";
	ui_label = "Input Whitepoint";
	ui_min = 1.0;
	ui_max = 5.0;
	ui_tooltip = "How much the dynamic range of the input is scaled";
	ui_category = "Global";
> = 4.0;

uniform float EXPOSURE <
	ui_type = "drag";
	ui_label = "Exposure";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_tooltip = "Camera exposure";
	ui_category = "Global";
> = 0.5;

uniform float OUTPUT_WP <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 5.0;
	hidden=1;
	ui_category = "Global";
> = 1.0;

uniform float SENSOR_NOISE <
	ui_type = "drag";
	ui_label = "Sensor Noise";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_tooltip = "Blends in digital sensor noise";
	ui_category = "Camera";
> = 0.3;

uniform float LENS <
	ui_label = "Lens Effects";
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_tooltip = "Blends in CA, fringing, and lens distortion";
	ui_category = "Camera";
> = 1;

uniform bool DEMOSAIC <
	ui_label = "Demoisaic";
	ui_category = "Camera";
	ui_tooltip = "Emulates demosaicing/debayering";
> = 0;


uniform int COLOR_TR <
	ui_label = "Color Transform";
	ui_type = "combo";
	ui_items = "iCam4\0MiniCam\0None\0";
	ui_tooltip = "Transform the output colors using data captured from actual cameras, \n"
				 "MiniCam was captured from a $10 mini camera I had lying around \n"
				 "iCam4 was captured from my 4th gen iPodTouch";
	ui_category = "Post";
> = 1;

uniform float SHARPENING <
	ui_type = "drag";
	ui_label = "Sharpening";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_tooltip = "Post sharpening, very crunchy and simple, as was common for digital cameras of the era";
	ui_category = "Post";
> = 1.0;


uniform float LCD_EM <
	ui_type = "drag";
	ui_label = "LCD Overlay";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_tooltip = "Blends in an LCD array mask (not a CRT emulation), if you want CRT instead use a dedicated shader for it";
	ui_category = "Post";
> = 0.3;
uniform bool CROP_AR <
	ui_label = "Crop Aspect Ratio";
	ui_tooltip = "Crop image to 4:3";
	ui_category = "Post";
> = 1;


#ifndef VERTICAL_RES
//============================================================================================
	#define VERTICAL_RES 360
//============================================================================================
#endif


namespace ZenSharpen {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	#define DS_RES VERTICAL_RES
	
	#define A_R (RES.x / RES.y)
	#define CAM_RES float2(A_R * DS_RES, DS_RES)
	#define FRAME_MOD ((FRAME_COUNT % 16) + 1)
	
	texture2D tHDR { DIVRES(1); Format = RGBA16F; MipLevels = 8; };
	sampler2D sHDR { Texture = tHDR; };
	
	texture2D tCamInput { Height = CAM_RES.y; Width = CAM_RES.x; Format = RGBA16F; MipLevels = 3; };
	sampler2D sCamInput { Texture = tCamInput; };
	
	texture2D tCamAux { Height = CAM_RES.y; Width = CAM_RES.x; Format = RGBA16F; MipLevels = 3; };
	sampler2D sCamAux { Texture = tCamAux; FILTER(POINT); };
	
	texture2D tCamAux1 { Height = CAM_RES.y; Width = CAM_RES.x; Format = RGBA16F; MipLevels = 3; };
	sampler2D sCamAux1 { Texture = tCamAux1; };
	
	
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float3 LinearToSRGB(float3 c)
	{
		return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
	}
	
	float3 TMO(float3 x, float wp)
	{
		//x = log2(x + 1.0) / wp;
		x = LinearToSRGB(saturate(x));
		
		//adjust contrast ratio to match old monitors
		return lerp(x, 1.0, 4.0 * rcp(230.0));
	}
	
	float3 ITMO(float3 x, float wp)
	{
		x = pow(x, 2.2); //not exactly science, just trying to balance to look nice
		return exp2(x * log2(wp)) - 1.0;
	}

	
	//adapted from https://research.activision.com/publications/archives/filmic-smaasharp-morphological-and-temporal-antialiasing
	float4 FastLanczos(sampler2D samp, float2 uv, float4 texSizeInv)
	{
	    // texSizeInv = float4(rcp(texSize), texSize);
	
	    float2 position = texSizeInv.zw * uv;
	    float2 centerPos = floor(position - 0.5) + 0.5;
	    float2 f = position - centerPos;
	    
	    float2 w0 = f*(f*(-0.6360*f + 1.2189) - 0.5829);
	    float2 w1 = f*(f*( 1.4295*f - 2.4419) + 0.0124) + 1.0;
	    f = 1.0 - f;
	    float2 w2 = f*(f*( 1.4295*f - 2.4419) + 0.0124) + 1.0;
	    float2 w3 = f*(f*(-0.6360*f + 1.2189) - 0.5829);
	    
	    float2 w12 = w1 + w2;
	    float2 tc12 = texSizeInv.xy * (centerPos + w2 / w12);
	    float4 centerColor = tex2Dlod(samp, float4(tc12.x, tc12.y, 0,0));
	    
	    float2 tc0 = texSizeInv.xy * (centerPos - 1.0);
	    float2 tc3 = texSizeInv.xy * (centerPos + 2.0);
	    float4 color = tex2Dlod(samp, float4(tc12.x, tc0.y,  0,0)) * (w12.x * w0.y ) +
	                   tex2Dlod(samp, float4(tc0.x,  tc12.y, 0,0)) * (w0.x  * w12.y) +
	                   centerColor                                 * (w12.x * w12.y) +
	                   tex2Dlod(samp, float4(tc3.x,  tc12.y, 0,0)) * (w3.x  * w12.y) +
	                   tex2Dlod(samp, float4(tc12.x, tc3.y,  0,0)) * (w12.x * w3.y );
	    return color * rcp(w12.x*w0.y + w0.x*w12.y + w12.x*w12.y + w3.x*w12.y + w12.x*w3.y);
	} //0.97 * 

	float4 hash42(float2 inp, float2 res)
	{
	    uint pg = asuint(res.x * res.x * inp.y + inp.x * res.x);
	    uint state = pg * 747796405u + 2891336453u;
	    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	    uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
	    return float4(RGBA) / 0xFFu;
	}
		
	float3 GNoise(float2 uv)
	{
		float3 x = hash42(uv + float2(0.1 * (FRAME_COUNT % 256), 0.0), CAM_RES).rgb;
		
		float3 a = x - 0.5;
		float3 d = round(x);
		float3 f = pow(2*abs(a), 12.0);
		return frac(saturate(lerp(0.25 + 0.5 * x, d, f)) );
	}


	float3 RGBToYCbCr(float3 rgb)
	{
		const float3x3 ConMat = float3x3(
		     0.299,    0.587,    0.114,
		    -0.168736, -0.331264, 0.5,
		     0.5,     -0.418688, -0.081312
		);
	
	    return mul(ConMat, rgb);
	}
	
	float3 YCbCrToRGB(float3 ycc)
	{
		const float3x3 ConMat = float3x3(
		    1.0,  0.0,      1.402,
		    1.0, -0.344136, -0.714136,
		    1.0,  1.772,     0.0
		);
	
	    return mul(ConMat, ycc);
	}

	float2 WarpUV(float2 uv, float a)
	{
		a *= LENS;
		//if(!LENS) return uv;
		float ar = 0.8;//RES.y / RES.x;
	
		float2 uvs = float2(1.0,ar) * (2*uv-1);
		a /= 0.2 + dot(uvs, uvs);
		
		return 0.5 + (1.0 - a) * 0.5 * float2(1.0,rcp(ar)) * uvs;
	}



	float3 CorrectMiniCam(float3 c)
	{
		const float3x3 iCamMat = float3x3(
		     0.95993,  0.06671, -0.02664,
		    -0.02716,  1.01039,  0.01676,
		    -0.07416, -0.07348,  1.14764
		);
		
	    const float3x3 minCamMat = float3x3(
		     0.86779,  0.11624,  0.01597,
		     0.02831,  0.90557,  0.06612,
		    -0.03684, -0.20416,  1.24100
		);
		
		
		switch(COLOR_TR)
		{
			case 0:
				return saturate(mul(iCamMat, c));
			case 1:
				return saturate(mul(minCamMat, c));
		}
	    return c;
	}

	//=======================================================================================
	//Passes
	//=======================================================================================
	
	float4 ITMOPS(PS_INPUTS) : SV_Target
	{
		return float4(ITMO(GetBackBuffer(uv), INPUT_WP), 1);
	}
	
	
		
	#define TL(S, xy) tex2Dlod(S, float4(xy,0,0))
	
	float4 TransferPS(PS_INPUTS) : SV_Target
	{
		float2 uvs;
		
		float mip = max(log2(1.0 +  CAM_RES * fwidth(uv)).x - 0.0, 0.0);
		
		float r = tex2Dlod(sHDR, float4(WarpUV(uv, 0.0030), 0, mip) ).x;
		float g = tex2Dlod(sHDR, float4(WarpUV(uv, 0.0015), 0, mip) ).g;
		float b = tex2Dlod(sHDR, float4(WarpUV(uv, 0.0000), 0, mip) ).b;

		float3 col = float3(r,g,b);//ITMO(, INPUT_WP);
		
		col = lerp(1.0, 0.1 + 1.9 * GNoise(uv), SENSOR_NOISE * (0.65 + 0.35 * saturate(col)) ) * col;
		
		// Debayering
		
		//col.rb += 0.5 * ddx(col.rb);
		//col.rb += 0.5 * ddy(col.rb);
		//col.g  += 0.5 * (ddx(col.g) + ddy(col.g));
		
		return float4(col,1);
	}
	
	float4 DebayerPS(PS_INPUTS) : SV_Target
	{
		if(DEMOSAIC)
		{
			float2 rb = tex2Dlod(sCamInput, float4(uv,0,1)).rb;
			
			float g = 0.0;
			
			float2 fp = 0.5 * rcp(CAM_RES);
			
			
			// Truly beautiful code
			g = frac(0.6 * (vpos.x + vpos.y)) > 0.25 ? 
				TL(sCamInput, uv).g :
				0.25 * (TL(sCamInput, uv + float2( 1, 0) * fp).g +
					    TL(sCamInput, uv + float2(-1, 0) * fp).g +
					    TL(sCamInput, uv + float2( 0, 1) * fp).g +
					    TL(sCamInput, uv + float2( 0,-1) * fp).g);
			
			
			return float4(rb.x,g,rb.y,1);
		}
		else
		{
			return TL(sCamInput, uv);
		}
	}
	
	float4 FringePS(PS_INPUTS) : SV_Target
	{
		float3 cen = TL(sCamAux, uv).rgb;
		
		float2 hp = 0.75 * rcp(CAM_RES);
		float3 A = TL(sCamAux, uv + float2( 1, 1) * hp).rgb;
		float3 B = TL(sCamAux, uv + float2( 1,-1) * hp).rgb;
		float3 C = TL(sCamAux, uv + float2(-1, 1) * hp).rgb;
		float3 D = TL(sCamAux, uv + float2(-1,-1) * hp).rgb;
		
		//float3 col = TMO(tex2D(sCamInput, xy).rgb, OUTPUT_WP);
		
		float3 col = cen;
		float3 blu = 0.25 * (A+B+C+D);
		
		col = lerp(cen, blu, LENS * float3(0.25,0.0,0.75));
		
		col = TMO(EXPOSURE * col, OUTPUT_WP);
		col = CorrectMiniCam(col);
		
		return float4(0.5 + 0.5 * RGBToYCbCr(col),1);
	}
	
	float4 PostPS(PS_INPUTS) : SV_Target
	{
		float3 cen = TL(sCamAux1, uv).rgb;
		
		float2 hp = 0.75 * rcp(CAM_RES);
		float3 A = TL(sCamAux1, uv + float2( 1, 1) * hp).rgb;
		float3 B = TL(sCamAux1, uv + float2( 1,-1) * hp).rgb;
		float3 C = TL(sCamAux1, uv + float2(-1, 1) * hp).rgb;
		float3 D = TL(sCamAux1, uv + float2(-1,-1) * hp).rgb;
		
		float lap = cen.x - 0.25 * (A.x+B.x+C.x+D.x);
		
		return float4(cen.x + SHARPENING * lap, cen.yz, 1);
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float4 BlendPS(PS_INPUTS) : SV_Target
	{
		float Y = tex2D(sCamAux, uv).x;
		float2 CbCr = tex2Dlod(sCamAux, float4(uv, 0, 1) ).yz;
	
		uint ix = uint( (vpos.x / ceil(RES.y / 1280.0) ) % 3);
		float3 cm = lerp(1.0, 0.25 + 0.75 * float3(ix==0,ix==1,ix==2), LCD_EM);
		
		cm *= CROP_AR ? (2.0 * abs(vpos.x - 0.5*RES.x) < (4.0/3.0) * RES.y) : 1.0;
		
		return float4(cm,1) * float4(YCbCrToRGB(2.0 * float3(Y, CbCr) - 1.0), 1.0);
		
		//return FastLanczos(sCamInput, xy, float4(rcp(CAM_RES), CAM_RES));
	}
	
	technique NostalgiaBait <
		ui_label = "Azen: Nostalgia Bait";
		  ui_tooltip =        
		        "Azen - Nostalgia Bait           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nThe pinnacle of realism, a shitty phone camera from 2010"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(ITMOPS, tHDR); }
		pass {	PASS1(TransferPS, tCamInput); }
		pass {	PASS1(DebayerPS, tCamAux); }
		pass {	PASS1(FringePS, tCamAux1); }
		pass {	PASS1(PostPS,  tCamAux); }
		pass {	PASS0(BlendPS); }
	}
}
