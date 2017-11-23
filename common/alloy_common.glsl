#define M_PI 3.1415926535897932384626433832795

#define DISTANCE_ATTENUATION_MULT 0.001


float gamma_to_linear1(float c) {
  //http://chilliant.blogspot.de/2012/08/srgb-approximations-for-hlsl.html
  return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

vec3 gamma_to_linear3(vec3 c) {
  //http://chilliant.blogspot.de/2012/08/srgb-approximations-for-hlsl.html
  return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

vec3 linear_to_gamma3(vec3 c) {
  vec3 S1 = sqrt(c);
  vec3 S2 = sqrt(S1);
  vec3 S3 = sqrt(S2);
  return 0.585122381 * S1 + 0.783140355 * S2 - 0.368262736 * S3;
}

vec3 fixNormalSample(vec3 v, bool flipY)
{
	vec3 res = (v - vec3(0.5,0.5,0.5))*2.0;
	res.y = flipY ? -res.y : res.y;
	return res;
}

vec3 fixBinormal(vec3 n, vec3 t, vec3 b)
{
	vec3 nt = cross(n,t);
	return sign(dot(nt,b))*nt;
}

vec3 rotate(vec3 v, float a)
{
	float angle =a*2.0*M_PI;
	float ca = cos(angle);
	float sa = sin(angle);
	return vec3(v.x*ca+v.z*sa, v.y, v.z*ca-v.x*sa);
}

float lampAttenuation(float distance)
{
	return 1.0/(1.0+DISTANCE_ATTENUATION_MULT*distance*distance);
}
