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
	Azen: PreCorrect - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon

*/
//========================================================================

#include "ReShade.fxh"
#include "AzenCommon.fxh"


#ifndef PERFORMANCE_MODE
	//============================================================================================
		#define PERFORMANCE_MODE 1
	//============================================================================================
	#endif


uniform float KERNEL_SHAPE <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Detail Precision";
	hidden = true;
	ui_tooltip = "Lower values effect larger areas, higher values affect finer details";
> = 1.0;

uniform float COLOR_NORM <
	ui_type = "drag";
	ui_label = "Color Normalization";
	ui_tooltip = "Removes tint from the image";
	ui_min = 0.0; 
	ui_max = 1.0;
> = 1.0;

uniform float LC_NORM <
	ui_type = "drag";
	ui_label = "Contrast Normalization";
	ui_min = -1.0; 
	ui_max = 1.0;
> = 0.5;

uniform float CONTRAST <
	ui_type = "drag";
	ui_label = "Contrast";
	ui_min = -0.5; 
	ui_max = 0.5;
> = 0.0;

uniform float HUE_SHIFT <
	ui_type = "drag";
	ui_label = "Hue";
	ui_min = -1.0; 
	ui_max = 1.0;
	hidden = 1;
> = 0.0;

uniform float SATURATION <
	ui_type = "drag";
	ui_label = "Saturation";
	ui_min = 0.001; 
	ui_max = 2.0;
> = 1.0;

uniform int TEMPERATURE <
	ui_type = "drag";
	ui_label = "Temperature";
	ui_tooltip = "Color Temperature";
	ui_min = 1000; 
	ui_max = 16000;
	//ui_step = 10;
> = 6500;

uniform float EXPOSURE <
	ui_type = "drag";
	ui_label = "Exposure";
	ui_tooltip = "Normalized Exposure, drag to 0 to disable";
	ui_min = 0.0; 
	ui_max = 2.0;
> = 0.0;

uniform bool SHOW_ORIGINAL <
	ui_label = "Show Original";
> = 0;

#define DMULT 0.5

#if(PERFORMANCE_MODE)
	#define TEX_FORMAT RGBA16F
#else
	#define TEX_FORMAT RGBA32F
#endif

namespace ZenAutoGrade {
	texture BlurTex0  { DIVRES(2); Format = TEX_FORMAT; };
	texture BlurTex1  { DIVRES(2); Format = TEX_FORMAT; MipLevels = 8; };
	
	texture DownTex0 { DIVRES(4); Format = TEX_FORMAT; };
	texture DownTex1 { DIVRES(8); Format = TEX_FORMAT; };
	texture DownTex2 { DIVRES(16); Format = TEX_FORMAT; };
	texture DownTex3 { DIVRES(32); Format = TEX_FORMAT; };
	texture DownTex4 { DIVRES(64); Format = TEX_FORMAT; };
	texture DownTex5 { DIVRES(128); Format = TEX_FORMAT; };
	texture DownTex6 { DIVRES(256); Format = TEX_FORMAT; };
	texture DownTex7 { DIVRES(512); Format = TEX_FORMAT; };


	texture UpTex6 { DIVRES(256); Format = TEX_FORMAT; };
	texture UpTex5 { DIVRES(128); Format = TEX_FORMAT; };
	texture UpTex4 { DIVRES(64); Format = TEX_FORMAT; };
	texture UpTex3 { DIVRES(32); Format = TEX_FORMAT; };
	texture UpTex2 { DIVRES(16); Format = TEX_FORMAT; };
	texture UpTex1 { DIVRES(8); Format = TEX_FORMAT; };
	texture UpTex0 { DIVRES(4); Format = TEX_FORMAT; };

	sampler BlurSam0  { Texture = BlurTex0;  };
	sampler BlurSam1  { Texture = BlurTex1; FILTER(POINT); };
	
	sampler DownSam0 { Texture = DownTex0; };
	sampler DownSam1 { Texture = DownTex1; };
	sampler DownSam2 { Texture = DownTex2; };
	sampler DownSam3 { Texture = DownTex3; };
	sampler DownSam4 { Texture = DownTex4; };
	sampler DownSam5 { Texture = DownTex5; };
	sampler DownSam6 { Texture = DownTex6; };
	sampler DownSam7 { Texture = DownTex7; };
	
	sampler UpSam6 { Texture = UpTex6; };
	sampler UpSam5 { Texture = UpTex5; };
	sampler UpSam4 { Texture = UpTex4; };
	sampler UpSam3 { Texture = UpTex3; };
	sampler UpSam2 { Texture = UpTex2; };
	sampler UpSam1 { Texture = UpTex1; };
	sampler UpSam0 { Texture = UpTex0; };
	
	texture tBBDS { DIVRES(1); Format = RGB10A2; MipLevels = 8; };
	sampler sBBDS { Texture = tBBDS; FILTER(POINT); };
	
	//=============================================================================
	//Tonemappers
	//=============================================================================
	
	//=============================================================================
	//Functions
	//=============================================================================
	#define OFF 1.0
	float4 DUSample(sampler input, float2 xy, float div)
	{
	    float2 hp = 2.0 * div * rcp(RES);
	  
		float4 acc;
		
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y));
		
		acc += 0.0625 * tex2D(input, xy + float2(-hp.x, 0));
		acc += 0.125 * tex2D(input, xy + float2(0, 0));
		acc += 0.0625 * tex2D(input, xy + float2(hp.x, 0));
		
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, -hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y));
	  
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, -hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y));
		
	    return acc;
	
	}
	
	float3 SRGBtoOKLAB(float3 c) 
	{
	    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
		float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
		float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;
	
	    float l_ = pow(l, 0.3334);
	    float m_ = pow(m, 0.3334);
	    float s_ = pow(s, 0.3334);
	
	   return float3(
	        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
	        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
	        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_);
	}
	
	float3 OKLABtoSRGB(float3 c) 
	{
	    float l_ = c.x + 0.3963377774f * c.y + 0.2158037573f * c.z;
	    float m_ = c.x - 0.1055613458f * c.y - 0.0638541728f * c.z;
	    float s_ = c.x - 0.0894841775f * c.y - 1.2914855480f * c.z;
	
	    float l = l_*l_*l_;
	    float m = m_*m_*m_;
	    float s = s_*s_*s_;
	
	    return float3(
			 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
			-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
			-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
	}
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy,conVr.xy)) );
	}
	
	//=============================================================================
	//Down Passes
	//=============================================================================
	float4 PrepPS(PS_INPUTS) : SV_Target
	{
		float3 c	= GetBackBuffer(xy);
		float3 lab  = SRGBtoOKLAB(c);
		return float4(lab.yz, lab.x, lab.x*lab.x);
	}
	
	float4 Down0(PS_INPUTS) : SV_Target
	{
		return DUSample(BlurSam0, xy, 2.0);
	}
	
	float4 Down1(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam0, xy, 4.0);
	}
	
	float4 Down2(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam1, xy, 8.0);
	}
	
	float4 Down3(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam2, xy, 16.0);
	}
	
	float4 Down4(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam3, xy, 32.0);
	}
	
	float4 Down5(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam4, xy, 64.0);
	}
	
	float4 Down6(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam5, xy, 128.0);
	}
	
	float4 Down7(PS_INPUTS) : SV_Target
	{
		return DUSample(DownSam6, xy, 256.0);
	}
	
	float4 CopyBBPS(PS_INPUTS) : SV_Target
	{
		return float4(pow(GetBackBuffer(xy), 2.2), 1.0);
	}
	
	//=============================================================================
	//Up Passes
	//=============================================================================
	
	//Not actually normalized anymore but the difference is almost 0
	#define coef00 lerp(0.2997328570, 0.0, KERNEL_SHAPE)
	#define coef0  lerp(0.2332857140, 0.08, KERNEL_SHAPE)
	#define coef1  lerp(0.1592857140, 0.09, KERNEL_SHAPE)
	#define coef2  lerp(0.1301857140, 0.1, KERNEL_SHAPE)
	#define coef3  lerp(0.0772857143, 0.1, KERNEL_SHAPE)
	#define coef4  lerp(0.0460000000, 0.1, KERNEL_SHAPE)
	#define coef5  lerp(0.0199085714, 0.1, KERNEL_SHAPE)
	#define coef6  lerp(0.0170000000, 0.1, KERNEL_SHAPE)
	#define coef7  lerp(0.0170000000, 0.33, KERNEL_SHAPE)
	
	#define KS sqrt(1.0 - KERNEL_SHAPE)
	
	float4 Up6(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef6 * tex2D(DownSam6, xy) + coef7 * DUSample(DownSam7, xy, 128.0);
	}
	
	float4 Up5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef5 * tex2D(DownSam5, xy) + DUSample(UpSam6, xy, 64.0);
	}
	
	float4 Up4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef4 * tex2D(DownSam4, xy) + DUSample(UpSam5, xy, 32.0);
	}
	
	float4 Up3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef3 * tex2D(DownSam3, xy) + DUSample(UpSam4, xy, 16.0);
	}
	
	float4 Up2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef2 * tex2D(DownSam2, xy) + DUSample(UpSam3, xy, 8.0);
	}
	
	float4 Up1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef1 * tex2D(DownSam1, xy) + DUSample(UpSam2, xy, 4.0);
	}
	
	float4 Up0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef0 * tex2D(DownSam0, xy) + DUSample(UpSam1, xy, 2.0);
	}
	
	float4 Up00(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return coef00 * tex2D(BlurSam0, xy) + DUSample(UpSam0, xy, 2.0);
	}
	
	//=============================================================================
	//Blend Passes
	//=============================================================================
	
	float3 BlackbodyRGB(float t)
	{
	    float3 b = float3(1.45854777,2.35661298,5.4192281) / (exp(float3(23588.967, 26644.018, 31972.820) / t) - 1.0);
	    b = b.r > 1e-32 ? b / (max(max(b.r, b.g), b.b)) : float3(1.0,0.0,0.0);
	    
	    float tm = 1.0 - rcp( 0.003 * abs(t) + 1.0 );
	    
	    return b / (GetLuminance(b) + 1e-32);
	}
	
	float4 DisplayDebug(float2 xy)
	{
		float4 data = tex2Dlod(BlurSam1, float4(xy,0,1));
		float3 c = SRGBtoOKLAB( saturate(pow(tex2Dlod(sBBDS, float4(xy,0,2)).rgb,rcp(2.2))) );
		
		float alpha = all( abs(xy-0.5) <= 0.5);
		
		
		data.xy = -COLOR_NORM * data.xy;
		data.z = c.x;
		c = OKLABtoSRGB(data.zxy * float3(1.0,1.0.xx));
		
		c = IReinJ(c,HDR);
		c *= BlackbodyRGB(TEMPERATURE);
		c = ReinJ(c,HDR);
		
		return float4(c, alpha);//data.w;
	}
	
	float EnableDebug(float2 xy, inout float3 c, inout float4 d, float sat)
	{
		float4 td = tex2Dlod(BlurSam1, float4(xy,0,1));
		float3 tc = tex2Dlod(sBBDS, float4(xy,0,2)).rgb;
		
		//float3 clip = max(1.0 - ceil(tc), floor(tc));
		tc = lerp(GetLuminance(tc), tc, sat); 
		tc = pow(tc, rcp(2.2));
		
		//tc = lerp(tc, clip, any(abs(clip) > 0.003));
		
		float alpha = all( abs(xy-0.5) <= 0.5);
		
		c = lerp(c,tc,alpha);
		d = lerp(d,td,alpha); 
		
		return alpha;
	}
	
	//returns sd and angle
	float2 GetCircle(float2 xy, float3 circle)
	{
		float l = distance(xy,circle.xy) - circle.z;
		
		float2 d = xy - circle.xy;
		float a = 0.5 + 0.5 * atan2(d.y,d.x) / 3.14159;
		
		return float2(l,a);
	}
	
	float3 BlendPS(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float4 GD = tex2D(BlurSam1,xy);
		GD.zw = max(GD.zw, 0.003);
		float3 c = GetBackBuffer(xy);
	
		
		float m = min(c.r, min(c.g,c.b));
		float M = max(c.r, max(c.g,c.b));
		float mask = 1.0 - (M - m) / (M + 0.003);
		mask = 1.0 - mask*mask*mask;
		//float grayA = EnableDebug(4.0*xy-float2(3.0,2.0), c, GD, 0.0);

		//EnableDebug(4.0*xy-float2(3.0,2.0), f, GD, 1.0);
		//f = SRGBtoOKLAB(f);
		//float fsat = length(f.yz);
		
		
		//contrast norm
		float var = saturate(GD.w - GD.z*GD.z) / (GD.z + 0.03);
		float vars = rcp(30.0 * rcp(saturate(LC_NORM*LC_NORM) + 0.001) * var + 1.0);
		c = SRGBtoOKLAB(c);
		float3 f = c;
		
		//EnableDebug(4.0*xy-float2(3.0,2.0), f, GD, 1.0);
		
		float lap = c.x - GD.z;
		float grad = exp(-32.0*lap*lap);
		lap -= saturate( (c.x + lap) - 1.0);
		//c.x += 
		
		//color norm
		c.yz -= COLOR_NORM * GD.xy;
		
		c = lerp(f,c,mask);
		
		c.yz *= SATURATION + 0.5 * saturate(SATURATION) * saturate(COLOR_NORM);
		c = float3(c.x, length(c.yz), atan2(c.z,c.y));;
		c.z += 3.14159 * HUE_SHIFT;
		c = float3(c.x, c.y*cos(c.z), c.y*sin(c.z) );
		
		
		c.x += sign(LC_NORM) * 0.5 * grad * vars * lap;
		c = OKLABtoSRGB(c);
		
		
		
		
		c = IReinJ(saturate(c), HDR);	
		c *= BlackbodyRGB(clamp(TEMPERATURE,500,15500));
		//c = lerp(c, IReinJ(f,HDR), 0.5*ld);//Highlight preservation
		c *= EXPOSURE >= 0.001 ? EXPOSURE / (2.0*GD.w + 0.01) : 1.0;
		
		
		c = ReinJ(c, HDR);
		
		c = pow(c,2.2);
		float3 ci = c / (float3(c.g+c.b,c.r+c.b,c.r+c.g) + 0.003);
		
		ci /= max(ci.r, max(ci.g, ci.b));
		
		//display original
		c = pow(c, rcp(2.2));
		if(SHOW_ORIGINAL) EnableDebug(4.0*xy-float2(3.0,1.0), c, GD, 1.0);
		
		float3 r = float3(0.3,0.15,0.08);
		float3 g = float3(0.22,0.3,0.08);
		float3 b = float3(0.1,0.2,0.2);
		
		float3 ac = ci.r*r + ci.g*g + ci.b*b;
		//ac = SRGBtoOKLAB(ac);
		//ac.x = 0.7 + lap;
		//ac = OKLABtoSRGB(ac);
		
		
		return pow(c, (1.0 + CONTRAST));//GetLuminance(f);
		
		//float2 circle = GetCircle((2.0 * xy - 1.0) * float2(1.0,RES.y/RES.x), float3(1.412,0.0,0.5) );
		
		
		
		//float3 cirCol = ReinJ(BlackbodyRGB( (16000.0 * frac(circle.y + TEMPERATURE / 16000.0) ) ), 1.5,1,0);
		
		
		//cirCol = circle.x < -0.02 ? cirCol : ;
		
		//float cAlpha = circle.x
		
		//c = (1.0-CONTRAST)*c / (1.0 - CONTRAST*c);
		//c = pow(c,CONTRAST + 1.0);
		
		
		//return circle.x < 0.0 ? cirCol : c;
	}
	
	technique AzenPreCorrect <
		ui_label = "Azen: PreCorrect";
	    ui_tooltip =        
	        "Azen - PreCorrect           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nA color neutralizer for games to allow more consistent grading"
	        "\n"
	        "\n=================================================================================================";
	>	
	{
		pass {	PASS1(CopyBBPS, tBBDS); }
		pass {	VertexShader = PostProcessVS; PixelShader = PrepPS; RenderTarget0 = BlurTex0;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Down0; RenderTarget = DownTex0; } 
		pass {	VertexShader = PostProcessVS; PixelShader = Down1; RenderTarget = DownTex1; }
		pass {	VertexShader = PostProcessVS; PixelShader = Down2; RenderTarget = DownTex2; } 
		pass {	VertexShader = PostProcessVS; PixelShader = Down3; RenderTarget = DownTex3; }
		pass {	VertexShader = PostProcessVS; PixelShader = Down4; RenderTarget = DownTex4; }
		pass {	VertexShader = PostProcessVS; PixelShader = Down5; RenderTarget = DownTex5; }
		pass {	VertexShader = PostProcessVS; PixelShader = Down6; RenderTarget = DownTex6; }
		pass {	VertexShader = PostProcessVS; PixelShader = Down7; RenderTarget = DownTex7; }
		
		pass {	VertexShader = PostProcessVS; PixelShader = Up6; RenderTarget = UpTex6;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Up5; RenderTarget = UpTex5;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Up4; RenderTarget = UpTex4;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Up3; RenderTarget = UpTex3;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Up2; RenderTarget = UpTex2;}
		pass {	VertexShader = PostProcessVS; PixelShader = Up1; RenderTarget = UpTex1;} 
		pass {	VertexShader = PostProcessVS; PixelShader = Up0; RenderTarget = UpTex0; }
		pass {	VertexShader = PostProcessVS; PixelShader = Up00; RenderTarget = BlurTex1; }
		
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = BlendPS;
		}
	}
}