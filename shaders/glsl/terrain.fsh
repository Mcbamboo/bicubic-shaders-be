// __multiversion__
// This signals the loading code to prepend either #version 100 or #version 300 es as apropriate.

#include "fragmentVersionCentroid.h"

#if __VERSION__ >= 300
	#ifndef BYPASS_PIXEL_SHADER
		#if defined(TEXEL_AA) && defined(TEXEL_AA_FEATURE)
			_centroid in highp vec2 uv0;
			_centroid in highp vec2 uv1;
		#else
			_centroid in vec2 uv0;
			_centroid in vec2 uv1;
		#endif
	#endif
#else
	#ifndef BYPASS_PIXEL_SHADER
		varying vec2 uv0;
		varying vec2 uv1;
	#endif
#endif

varying vec4 color;
varying highp vec3 cpos;
varying highp vec3 wpos;
varying float wflag;

#ifdef UNDERWATER
varying float fogr;
#endif

#include "uniformShaderConstants.h"
#include "uniformPerFrameConstants.h"
#include "util.h"

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;
LAYOUT_BINDING(1) uniform sampler2D TEXTURE_1;
LAYOUT_BINDING(2) uniform sampler2D TEXTURE_2;

#include "bsbe.cs.glsl"

#ifdef waterbump

vec3 getTangent(vec3 normal){
	vec3 tangent = vec3(0, 0, 0);
	if(normal.x > 0.0){ tangent = vec3(0, 0, -1);
	} else if(normal.x < -0.5){ tangent = vec3(0, 0, 1);
	} else if(normal.y > 0.0){ tangent = vec3(1, 0, 0);
	} else if(normal.y < -0.5){ tangent = vec3(1, 0, 0);
	} else if(normal.z > 0.0){ tangent = vec3(1, 0, 0);
	} else if(normal.z < -0.5){ tangent = vec3(-1, 0, 0);
	}
	return tangent;
}

vec3 calcwnormal(vec3 normal){
	vec3 rawnormal = texture2D(TEXTURE_0, uv0-fract(cpos.xz)/4.0+fract(cpos.xz*0.1+TOTAL_REAL_WORLD_TIME*0.1)/4.0).rgb*0.6;
		rawnormal += texture2D(TEXTURE_0, uv0-fract(cpos.xz)/4.0+fract(cpos.xz*0.4-TOTAL_REAL_WORLD_TIME*0.2)/4.0).rgb*0.4;
		rawnormal = rawnormal*2.0-1.0;
		rawnormal.xy *= 0.2;

	vec3 tangent = getTangent(normal);
	vec3 binormal = normalize(cross(tangent, normal));
	mat3 tbnmatrix = mat3(tangent.x, binormal.x, normal.x, tangent.y, binormal.y, normal.y, tangent.z, binormal.z, normal.z);
		rawnormal = normalize(rawnormal*tbnmatrix);
	return rawnormal;
}
#endif

vec4 reflection(vec4 diff,vec3 normal,highp vec3 uppos,vec3 lcolor,float reftance,float reftivity,bool water){
	highp vec3 vvector = normalize(-wpos);
	highp vec3 rvector = reflect(normalize(wpos),normal);
	vec3 skycolor = rendersky(rvector,uppos);

	highp float fresnel = reftance+(1.0-reftance)*pow(1.0-max0(dot(normal,vvector)),5.0);
		fresnel = saturate(fresnel);

	if(water)diff = vec4(0.0,0.0,0.0,fresnel);
	diff = mix(diff,vec4(skycolor,1.0),fresnel);

	if(reftivity>0.9){
		highp vec3 lpos = vec3(-0.9848078,0.16477773,0.0);
		highp float ndh = pow(max0(dot(normal,normalize(vvector+lpos))),256.0);

		diff += vec4(lcolor,fresnel*length(lcolor));
		diff += ndh*vec4(skycolor,1.0)*dfog;
	}
	diff.rgb *= max(uv1.x,smoothstep(0.845,0.87,uv1.y));
	return diff;
}

vec3 illumination(vec3 diff,vec3 normal,vec3 lcolor,float blmap,bool water){
	float dusk = min(smoothstep(0.3,0.5,blmap),smoothstep(1.0,0.8,blmap))*(1.0-rain);
	float night = smoothstep(1.0,0.2,blmap);

	float shadow = 1.0;
	#if !USE_ALPHA_TEST
		shadow = dside(shadow,0.0,normal.x);
	#else
		if(color.a == 0.0) shadow = dside(shadow,0.2,normal.x);
	#endif
 		shadow = mix(shadow,0.0,smoothstep(0.87,0.845,uv1.y));
		shadow = mix(shadow,0.0,rain);
	if(!water)shadow = mix(shadow,0.0,smoothstep(0.6,0.3,color.g));
		shadow = mix(shadow,1.0,smoothstep(blmap*pow(uv1.y,2.0),1.0,uv1.x));

	vec3 amblmap = vec3(0.2,0.3,0.5)*(1.0-saturate(rain*0.25+night*2.))*uv1.y;
	vec3 ambcolor = mix(mix(vec3(1.0,0.9,0.8),vec3(0.6,0.2,0.3),dusk),vec3(0.0,0.0,0.15),night);
		amblmap += lcolor;
		amblmap += ambcolor*shadow*uv1.y;

	diff *= amblmap;
	return diff;
}

void main()
{
#ifdef BYPASS_PIXEL_SHADER
	gl_FragColor = vec4(0, 0, 0, 0);
	return;
#else

#if USE_TEXEL_AA
	vec4 diffuse = texture2D_AA(TEXTURE_0, uv0);
#else
	vec4 diffuse = texture2D(TEXTURE_0, uv0);
#endif

#ifdef SEASONS_FAR
	diffuse.a = 1.0;
#endif

#if USE_ALPHA_TEST
	#ifdef ALPHA_TO_COVERAGE
	#define ALPHA_THRESHOLD 0.05
	#else
	#define ALPHA_THRESHOLD 0.5
	#endif
	if(diffuse.a < ALPHA_THRESHOLD)
		discard;
#endif

vec4 inColor = color;

#if defined(BLEND)
	diffuse.a *= inColor.a;
#endif

#ifndef SEASONS
	#if !USE_ALPHA_TEST && !defined(BLEND)
		diffuse.a = inColor.a;
	#endif
	if(color.g > color.b && color.a != 0.0){
		diffuse.rgb *= mix(normalize(inColor.rgb),inColor.rgb,0.5);
	} else {
		diffuse.rgb *= (color.a == 0.0)?inColor.rgb:sqrt(inColor.rgb);
	}
#else
	vec2 uv = inColor.xy;
	diffuse.rgb *= mix(vec3(1.0,1.0,1.0), texture2D(TEXTURE_2, uv).rgb*2.0, inColor.b);
	diffuse.rgb *= inColor.aaa;
	diffuse.a = 1.0;
#endif

	vec3 normal = normalize(cross(dFdx(cpos.xyz),dFdy(cpos.xyz)));
	bool water = wflag > 0.4 && wflag < 0.6;
	float reftance = 0.0, reftivity = 0.0;

	reftance = mix(reftance, 0.04, rain);
	reftivity = mix(reftivity, 0.5, rain);

#ifdef waterbump
	if(water){
		reftance = 0.2;
		reftivity = 1.0;
		normal = calcwnormal(normal);
	}
#endif

	float blmap = texture2D(TEXTURE_1,vec2(0,1)).r;
	float lsource = mix(mix(0.0,uv1.x,smoothstep(blmap*pow(uv1.y,2.0),1.0,uv1.x)),uv1.x,rain*uv1.y);
	vec3 lcolor = vec3(1.0,0.35,0.0)*lsource+pow(lsource,5.0)*0.6;

	diffuse.rgb = toLinear(diffuse.rgb);
	diffuse.rgb = illumination(diffuse.rgb,normal,lcolor,blmap,water);

	highp vec3 uppos = normalize(vec3(0.0,abs(wpos.y),0.0));
	vec3 newfc = rendersky(normalize(wpos),uppos);

#ifdef UNDERWATER
	#ifdef waterbump
		highp float caus = inoise(cpos.xz);
		if(!water) diffuse.rgb = vec3(0.3,0.5,0.8)*diffuse.rgb+saturate(caus)*diffuse.rgb*uv1.y;
	#endif
	diffuse.rgb += pow(uv1.x,3.0)*sqrt(diffuse.rgb)*(1.0-uv1.y);
	diffuse.rgb = mix(diffuse.rgb,toLinear(FOG_COLOR.rgb),pow(fogr,5.0));
#else
	diffuse = reflection(diffuse,normal,uppos,lcolor,reftance,reftivity,water);
#endif

	diffuse.rgb = mix(diffuse.rgb,newfc,saturate(length(wpos)*(0.001+0.003*rain)));

	diffuse.rgb = colorcorrection(diffuse.rgb);


	gl_FragColor = diffuse;

#endif
}
