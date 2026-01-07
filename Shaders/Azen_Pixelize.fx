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
Azen Pixelize - Authored by Daniel Oren-Ibarra "Zenteon"

Discord: https://discord.gg/PpbcqJJs6h
Patreon: https://patreon.com/Zenteon


*/
//========================================================================


#include "ReShade.fxh"
#include "AzenCommon.fxh"

uniform int DITHER_PATTERN <
ui_type = "combo";
ui_label = "Dither Pattern";
ui_items = "Bayer\0Golden Ratio\0Golden Ratio V\0Blue Noise\0White Noise\0";
> = 0;


uniform float PIXEL_SIZE <
ui_type = "slider";
ui_label = "Pixel Size";
ui_step = 0.5;
ui_min = 1.0;
ui_max = 8.0;
> = 3.0;

uniform float GAMMA <
ui_type = "drag";
ui_label = "Gamma";
ui_min = -1.0;
ui_max = 1.0;
> = 0.2;

uniform float DITHER_INTENSITY <
ui_type = "slider";
ui_label = "Dither Intensity";
ui_min = 0.0;
ui_max = 1.0;
> = 0.25;

uniform int QUANTIZE_DEPTH <
ui_type = "slider";
ui_label = "Quantization Amount";
ui_min = 2;
ui_max = 256;
> = 12;

namespace ZenSharp {

//=======================================================================================
//Textures/Samplers
//=======================================================================================

texture tBN < source = "AzenBN512.png"; >{ Width = 512; Height = 512; Format = RGBA8; };
sampler sBN { Texture = tBN; };

//=======================================================================================
//Functions
//=======================================================================================

float Bayer(uint2 p, uint level) //Thanks Marty
{
	p = (p ^ (p << 8u)) & 0x00ff00ffu;
	p = (p ^ (p << 4u)) & 0x0f0f0f0fu;
	p = (p ^ (p << 2u)) & 0x33333333u;
	p = (p ^ (p << 1u)) & 0x55555555u;     
	
	uint i = (p.x ^ p.y) | (p.x << 1);     
	i = reversebits(i); 
	i >>= 32 - level * 2;  
	return float(i) / float(1 << (2 * level));
}

float GRnoise(float2 xy)
{  
	const float2 igr2 = float2(0.754877666, 0.56984029); 
	xy *= igr2;
	return frac(xy.x + xy.y);
}

float GRnoiseV(float2 xy)
{  
	const float2 igr2 = float2(0.754877666, 0.56984029);
	float2 t = xy * igr2;
	float n = frac(t.x + t.y);
	return n < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
}

float hash12(float2 p)
{
	float3 p3  = frac(p.xyx * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

float cbt(float x)
{
	return (x -0.5) / QUANTIZE_DEPTH;
}

float GetDither(float2 pos, int T)
{
	[branch]
	switch(T) {
		case 0: return Bayer(pos, 3);
		case 1: return GRnoise(pos);
		case 2: return GRnoiseV(pos);
		case 3: return tex2Dfetch(sBN, pos % 512).x;
		case 4: return hash12(pos);
	}
	return 0;
}



//=======================================================================================
//Passes
//=======================================================================================


//=======================================================================================
//Blending
//=======================================================================================


float3 BlendPS(PS_INPUTS) : SV_Target
{
	float2 tr = RES / PIXEL_SIZE;
	xy = (floor(tr * xy) + 0.5) / tr;
	float3 c = GetBackBuffer(xy);
	
	float dither = 2.0 * DITHER_INTENSITY * (GetDither(xy*tr + 0.5, DITHER_PATTERN) - 0.5);
	c = sqrt(c);
	c = saturate(round(c * QUANTIZE_DEPTH + dither) / QUANTIZE_DEPTH);
	c = pow(c, 2.0 + GAMMA );
	return c;
}

technique AzenPixelize <
	ui_label = "Azen: Pixelize";
		ui_tooltip =        
			"Azen - Pixelize           \n"
			"\n================================================================================================="
			"\n"
			"\nPretty self explanatory, does the pixeling"
			"\n"
			"\n=================================================================================================";
	>	
{
	pass {	PASS0(BlendPS); }
}
}
