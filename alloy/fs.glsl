//////////////////////////////// Fragment shader
#version 120
#extension GL_ARB_shader_texture_lod : require

#include "../common/alloy_common.glsl"
#include "../common/parallax.glsl"

varying vec3 iFS_Normal;
varying vec2 iFS_UV;
varying vec3 iFS_Tangent;
varying vec3 iFS_Binormal;
varying vec3 iFS_PointWS;

uniform vec3 Lamp0Pos = vec3(0.0,0.0,70.0);
uniform vec3 Lamp0Color = vec3(1.0,1.0,1.0);
uniform float Lamp0Intensity = 1.0;
uniform vec3 Lamp1Pos = vec3(70.0,0.0,0.0);
uniform vec3 Lamp1Color = vec3(0.198,0.198,0.198);
uniform float Lamp1Intensity = 1.0;

uniform float AmbiIntensity = 1.0;
uniform float EmissiveIntensity = 1.0;

uniform int parallax_mode = 0;

uniform float tiling = 1.0;
uniform vec3 uvwScale = vec3(1.0, 1.0, 1.0);
uniform bool uvwScaleEnabled = false;
uniform float envRotation = 0.0;
uniform float tessellationFactor = 4.0;
uniform float heightMapScale = 1.0;
//uniform bool flipY = true;
uniform bool perFragBinormal = true;
//uniform bool sRGBBaseColor = true;

uniform sampler2D heightMap;
uniform sampler2D normalMap;
uniform sampler2D baseColorMap;
uniform sampler2D metallicMap;
uniform sampler2D roughnessMap;
uniform sampler2D aoMap;
uniform sampler2D emissiveMap;
uniform sampler2D specularLevel;
uniform sampler2D opacityMap;
uniform sampler2D environmentMap;

uniform mat4 viewInverseMatrix;

// Number of miplevels in the envmap
uniform float maxLod = 12.0;

// Actual number of samples in the table
uniform int nbSamples = 16;

// Irradiance spherical harmonics polynomial coefficients
// This is a color 2nd degree polynomial in (x,y,z), so it needs 10 coefficients
// for each color channel
uniform vec3 shCoefs[10];

// This must be included after the declaration of the uniform arrays since they
// can't be passed as functions parameters for performance reasons (on macs)
#include "../common/alloy_pbr_ibl.glsl"

float fit_roughness(float r)
{
// Fit roughness values to a more usable curve
	return r;
}

void main()
{
	vec3 normalWS = iFS_Normal;
	vec3 tangentWS = iFS_Tangent;
	vec3 binormalWS = perFragBinormal ?
		fixBinormal(normalWS,tangentWS,iFS_Binormal) : iFS_Binormal;

	vec3 cameraPosWS = viewInverseMatrix[3].xyz;
	vec3 pointToLight0DirWS = Lamp0Pos - iFS_PointWS;
	float pointToLight0Length = length(pointToLight0DirWS);
	pointToLight0DirWS *= 1.0 / pointToLight0Length;
	vec3 pointToLight1DirWS = Lamp1Pos - iFS_PointWS;
	float pointToLight1Length = length(Lamp1Pos - iFS_PointWS);
	pointToLight1DirWS *= 1.0 / pointToLight1Length;
	vec3 pointToCameraDirWS = normalize(cameraPosWS - iFS_PointWS);

	// ------------------------------------------
	// Parallax
	vec2 uvScale = vec2(1.0, 1.0);
	if (uvwScaleEnabled)
		uvScale = uvwScale.xy;
	vec2 uv = parallax_mode == 1 ? iFS_UV*tiling*uvScale : updateUV(
		heightMap,
		pointToCameraDirWS,
		normalWS, tangentWS, binormalWS,
		heightMapScale,
		iFS_UV,
		uvScale,
		tiling);

	// ------------------------------------------
	// Add Normal from normalMap
	vec3 fixedNormalWS = normalWS;  // HACK for empty normal textures
	vec3 normalTS = texture2D(normalMap,uv).xyz;
	if(length(normalTS)>0.0001)
	{
		normalTS = fixNormalSample(normalTS,false);
		fixedNormalWS = normalize(
			normalTS.x*tangentWS +
			normalTS.y*binormalWS +
			normalTS.z*normalWS );
	}
  
    float ndv = max(0.0f, dot(pointToCameraDirWS, fixedNormalWS));
  
	// ------------------------------------------
	// Compute material model (diffuse, specular & roughness)
	float dielectricSpec = 0.08 * texture2D(specularLevel,uv).r;
    vec3 dielectricColor = vec3(dielectricSpec, dielectricSpec, dielectricSpec);
	vec3 baseColor = gamma_to_linear3(texture2D(baseColorMap,uv).rgb);
	float metallic = texture2D(metallicMap,uv).r;
	float roughness = texture2D(roughnessMap,uv).r;
    float ambientOcclusion = gamma_to_linear1(texture2D(aoMap,uv).r);
    float specularOcclusion = specular_occlusion(ambientOcclusion, ndv);
  
	vec3 diffColor = baseColor * (1.0 - metallic);
	vec3 specColor = mix(dielectricColor, baseColor, metallic);

	// ------------------------------------------
	// Compute point lights contributions
	vec3 contrib0 = pointLightContribution(
			fixedNormalWS,
			pointToLight0DirWS,
			pointToCameraDirWS,
			diffColor,
			specColor,
            specularOcclusion,
			roughness,
			Lamp0Color,
			Lamp0Intensity,
			pointToLight0Length );
	vec3 contrib1 = pointLightContribution(
			fixedNormalWS,
			pointToLight1DirWS,
			pointToCameraDirWS,
			diffColor,
			specColor,
            specularOcclusion,
			roughness,
			Lamp1Color,
			Lamp1Intensity,
			pointToLight1Length );

	// ------------------------------------------
	// Image based lighting contribution
	vec3 contribE = computeIBL(
		environmentMap, envRotation, maxLod,
		nbSamples,
		normalWS, fixedNormalWS, tangentWS, binormalWS,
		pointToCameraDirWS,
		diffColor, specColor, roughness,
		ambientOcclusion * AmbiIntensity, specularOcclusion);

	// ------------------------------------------
	//Emissive
	vec3 emissiveContrib = gamma_to_linear3(texture2D(emissiveMap,uv).rgb) * EmissiveIntensity;

	// ------------------------------------------
	vec3 finalColor = contrib0 + contrib1 + contribE + emissiveContrib;

	// Final Color
	gl_FragColor = vec4(finalColor, texture2D(opacityMap,uv).r);
}
