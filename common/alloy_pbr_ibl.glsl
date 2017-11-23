#define M_INV_PI 0.31830988618379067153776752674503
#define M_INV_LOG2 1.4426950408889634073599246810019

float specular_occlusion(
  float ao,
	float ndv)
{
	// Gotanda's Specular occlusion approximation:
	// cf http://research.tri-ace.com/Data/cedec2011_RealtimePBR_Implementation_e.pptx pg59
	float d = ndv + ao;
	return clamp((d * d) - 1.0 + ao, 0.0, 1.0);
}

float normal_distrib(
	float ndh,
	float Roughness)
{
// use GGX / Trowbridge-Reitz, same as Disney and Unreal 4
// cf http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf p3
	float alpha = Roughness * Roughness;
	float tmp = alpha / max(1e-8,(ndh*ndh*(alpha*alpha-1.0)+1.0));
	return tmp * tmp * M_INV_PI;
}

vec3 fresnel(
	float vdh,
	vec3 F0)
{
// Schlick with Spherical Gaussian approximation
// cf http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf p3
	float sphg = pow(2.0, (-5.55473*vdh - 6.98316) * vdh);
	return F0 + (vec3(1.0, 1.0, 1.0) - F0) * sphg;
}

float direct_visibility(
  float vdh,
  float Roughness)
{
  // John Hable's approximation of Brian Karis' Schlick-Smith approximation.
  // cf http://www.filmicworlds.com/2014/04/21/optimizing-ggx-shaders-with-dotlh/
  float k = Roughness * Roughness * 0.5;
  return 1.0 / mix(k * k, 1.0, vdh * vdh);
}

float G1(
	float ndw, // w is either Ln or Vn
	float k)
{
// One generic factor of the geometry function divided by ndw
// NB : We should have k > 0
	return 1.0 / ( ndw*(1.0-k) + k );
}

float ibl_visibility(
	float ndl,
	float ndv,
	float Roughness)
{
// Schlick with Smith-like choice of k
// cf http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf p3
// visibility is a Cook-Torrance geometry function divided by (n.l)*(n.v)
	float k = Roughness * Roughness * 0.5;
	return G1(ndl,k)*G1(ndv,k);
}

vec3 microfacets_brdf(
	vec3 Nn,
	vec3 Ln,
	vec3 Vn,
	vec3 Ks,
	float Roughness)
{
  // Matches the remapping in our system that prevents Area Light artifacts.
  Roughness = mix(0.05, 1.0, Roughness);

	vec3 Hn = normalize(Vn + Ln);
	float vdh = max( 0.0, dot(Vn, Hn) );
	float ndh = max( 0.0, dot(Nn, Hn) );
	float ndl = max( 0.0, dot(Nn, Ln) );
	float ndv = max( 0.0, dot(Nn, Vn) );
	return fresnel(vdh,Ks) *
		( normal_distrib(ndh,Roughness) * direct_visibility(vdh,Roughness) / 4.0 );
}

vec3 microfacets_contrib(
	float vdh,
	float ndh,
	float ndl,
	float ndv,
	vec3 Ks,
	float Roughness)
{
// This is the contribution when using importance sampling with the GGX based
// sample distribution. This means ct_contrib = ct_brdf / ggx_probability
	return fresnel(vdh,Ks) * (ibl_visibility(ndl,ndv,Roughness) * vdh * ndl / ndh );
}

float diffuse_fresnel(
	float Df90,
	float ndw)
{
	// Spherical gaussian approximation as proposed by:
	// http://seblagarde.wordpress.com/2011/08/17/hello-world/
	float sphg = exp2((-5.55473 * ndw - 6.98316) * ndw);
	
	// cf http://disney-animation.s3.amazonaws.com/library/s2012_pbs_disney_brdf_notes_v2.pdf p14
	return 1.0 + (Df90 - 1.0) * sphg;
}

vec3 diffuse_brdf(
	vec3 Nn,
	vec3 Ln,
	vec3 Vn,
	vec3 Kd,
	float Roughness)
{
  // Matches the clamp in our system that prevents Area Light artifacts.
  Roughness = mix(0.05, 1.0, Roughness);
  
	vec3 Hn = normalize(Vn + Ln);
	float vdh = max( 0.0, dot(Vn, Hn) );
	float ndh = max( 0.0, dot(Nn, Hn) );
	float ndl = max( 0.0, dot(Nn, Ln) );
	float ndv = max( 0.0, dot(Nn, Vn) );
  
	// Impelementation of Disney's Burley BRDF.
	// cf http://disney-animation.s3.amazonaws.com/library/s2012_pbs_disney_brdf_notes_v2.pdf p14
	float Df90 = 0.5 + (2.0 * vdh * vdh * Roughness);
	return Kd * (M_INV_PI * diffuse_fresnel(Df90, ndl) * diffuse_fresnel(Df90, ndv));
}

void computeOrtho(vec3 A, out vec3 B, out vec3 C)
{
	B = (abs(A.z) < 0.999) ? vec3(-A.y, A.x, 0.0 )*inversesqrt(1.0-A.z*A.z) :
		vec3(0.0, -A.z, A.y)*inversesqrt(1.0-A.x*A.x) ;
	C = cross( A, B );
}

vec3 irradianceFromSH(vec3 n)
{
	return (shCoefs[0]*n.x + shCoefs[1]*n.y + shCoefs[2]*n.z + shCoefs[3])*n.x
		+ (shCoefs[4]*n.y + shCoefs[5]*n.z + shCoefs[6])*n.y
		+ (shCoefs[7]*n.z + shCoefs[8])*n.z
		+ shCoefs[9];
}

vec3 importanceSampleGGX(vec2 Xi, vec3 A, vec3 B, vec3 C, float roughness)
{
	float a = roughness*roughness;
	float cosT = sqrt((1.0-Xi.y)/(1.0+(a*a-1.0)*Xi.y));
	float sinT = sqrt(1.0-cosT*cosT);
	float phi = 2.0*M_PI*Xi.x;
	return (sinT*cos(phi)) * A + (sinT*sin(phi)) * B + cosT * C;
}

float probabilityGGX(float ndh, float vdh, float Roughness)
{
	return normal_distrib(ndh, Roughness) * ndh / (4.0*vdh);
}

float distortion(vec3 Wn)
{
	// Computes the inverse of the solid angle of the (differential) pixel in
	// the environment map pointed at by Wn
	float sinT = sqrt(1.0-Wn.y*Wn.y);
	return sinT;
}

float computeLOD(vec3 Ln, float p, int nbSamples, float maxLod)
{
	return max(0.0, (maxLod-1.5) - 0.5*(log(float(nbSamples)) + log( p * distortion(Ln) ))
		* M_INV_LOG2);
}

vec3 samplePanoramicLOD(sampler2D map, vec3 dir, float lod)
{
	float n = length(dir.xz);
	vec2 pos = vec2( (n>0.0000001) ? dir.x / n : 0.0, dir.y);
	pos = acos(pos)*M_INV_PI;
	pos.x = (dir.z > 0.0) ? pos.x*0.5 : 1.0-(pos.x*0.5);
	pos.y = 1.0-pos.y;
        return texture2DLod(map, pos, lod).rgb;
}

vec3 pointLightContribution(
	vec3 fixedNormalWS,
	vec3 pointToLightDirWS,
	vec3 pointToCameraDirWS,
	vec3 diffColor,
	vec3 specColor,
    float specularOcclusion,
	float roughness,
	vec3 LampColor,
	float LampIntensity,
	float LampDist)
{
	// Note that the lamp intensity is using ˝computer games units" i.e. it needs
	// to be multiplied by M_PI.
	// Cf https://seblagarde.wordpress.com/2012/01/08/pi-or-not-to-pi-in-game-lighting-equation/

	return (M_PI * max(dot(fixedNormalWS,pointToLightDirWS), 0.0)) * ( (
		diffuse_brdf(
			fixedNormalWS,
			pointToLightDirWS,
			pointToCameraDirWS,
            diffColor,
			roughness)
        + specularOcclusion
            * microfacets_brdf(
                fixedNormalWS,
                pointToLightDirWS,
                pointToCameraDirWS,
                specColor,
                roughness) ) *LampColor*(lampAttenuation(LampDist)* LampIntensity) );
}

void computeSamplingFrame(
	in vec3 iFS_Tangent,
	in vec3 iFS_Binormal,
	in vec3 fixedNormalWS,
	out vec3 Tp,
	out vec3 Bp)
{
	Tp = normalize(iFS_Tangent
		- fixedNormalWS*dot(iFS_Tangent, fixedNormalWS));
	Bp = normalize(iFS_Binormal
		- fixedNormalWS*dot(iFS_Binormal,fixedNormalWS)
		- Tp*dot(iFS_Binormal, Tp));
}


//- Return the i*th* number from the Van Der Corput sequence.
float VanDerCorput(
	sampler2D vanDerCorputMap, 
	int i, 
	int vanDerCorputMapWidth,
	int vanDerCorputMapHeight,
	int nbSamples)
{
  float xInVanDerCorputTex = (float(i)+0.5) / vanDerCorputMapWidth;
  float yInVanDerCorputTex = 0.5 / vanDerCorputMapHeight; // First row pixel
  return texture2D(vanDerCorputMap, vec2(xInVanDerCorputTex, yInVanDerCorputTex)).x;
}

//- Return the i*th* couple from the hammerlsey sequence.
//- nbSample is required to get an uniform distribution. nbSample has to be less than 1024.
vec2 hammersley2D(
	sampler2D vanDerCorputMap, 
	int i, 
	int vanDerCorputMapWidth,
	int vanDerCorputMapHeight,
	int nbSamples)
{
  return vec2(
		(float(i)+0.5) / float(nbSamples),
		VanDerCorput(vanDerCorputMap, i, vanDerCorputMapWidth, vanDerCorputMapHeight, nbSamples)
		);
}

vec3 IBLSpecularContributionQMC(
	sampler2D environmentMap, 
	float envRotation, 
	float maxLod,
	sampler2D vanDerCorputMap, 
	int vanDerCorputMapWidth,
	int vanDerCorputMapHeight,
	int nbSamples,
	vec3 normalWS,
	vec3 fixedNormalWS, 
	vec3 Tp, 
	vec3 Bp,
	vec3 pointToCameraDirWS,
	vec3 specColor, 
	float roughness)
{
	vec3 sum = vec3(0.0,0.0,0.0);

	float ndv = max( 1e-8, abs(dot( pointToCameraDirWS, fixedNormalWS )) );

	for(int i=0; i<nbSamples; ++i)
	{
		vec2 Xi = hammersley2D(vanDerCorputMap, i, vanDerCorputMapWidth, vanDerCorputMapHeight, nbSamples);
		vec3 Hn = importanceSampleGGX(Xi,Tp,Bp,fixedNormalWS,roughness);
		vec3 Ln = -reflect(pointToCameraDirWS,Hn);

		float ndl = dot(fixedNormalWS, Ln);

		// Horizon fading trick from http://marmosetco.tumblr.com/post/81245981087
		const float horizonFade = 1.3;
		float horiz = clamp( 1.0 + horizonFade * dot(normalWS, Ln), 0.0, 1.0 );
		horiz *= horiz;
		ndl = max( 1e-8, ndl );

		float vdh = max( 1e-8, abs(dot(pointToCameraDirWS, Hn)) );
		float ndh = max( 1e-8, abs(dot(fixedNormalWS, Hn)) );
		float lodS = roughness < 0.01 ? 0.0 :
			computeLOD(
				Ln,
				probabilityGGX(ndh, vdh, roughness),
				nbSamples,
				maxLod);
		sum +=
			samplePanoramicLOD(environmentMap,rotate(Ln,envRotation),lodS) *
			microfacets_contrib(
				vdh, ndh, ndl, ndv,
				specColor,
				roughness) * horiz;
	}

	return sum / nbSamples;
}

vec3 computeIBL(
	sampler2D environmentMap,
	float envRotation, 
	float maxLod,
	sampler2D vanDerCorputMap, 
	int vanDerCorputMapWidth,
	int vanDerCorputMapHeight,
	int nbSamples,
	vec3 normalWS,
	vec3 fixedNormalWS, 
	vec3 iFS_Tangent, 
	vec3 iFS_Binormal,
	vec3 pointToCameraDirWS,
    vec3 diffColor, 
    vec3 specColor, 
    float roughness,
    float ambientOcclusion, 
    float specularOcclusion)
{
	vec3 Tp,Bp;
	computeSamplingFrame(iFS_Tangent, iFS_Binormal, fixedNormalWS, Tp, Bp);

	vec3 specularE = IBLSpecularContributionQMC(
		environmentMap, 
		envRotation, 
		maxLod,
		vanDerCorputMap,
		vanDerCorputMapWidth,
		vanDerCorputMapHeight,
		nbSamples,
		normalWS,
		fixedNormalWS, 
		Tp, 
		Bp,
		pointToCameraDirWS,
		specColor, 
		roughness);
  
    // Apply specular occlusion and fake inter-reflection for dark areas.
    vec3 diffuseAO = ambientOcclusion * irradianceFromSH(rotate(fixedNormalWS,envRotation));
	return diffuseAO * diffColor
            + mix(diffuseAO * specColor, specularE, specularOcclusion);
}
