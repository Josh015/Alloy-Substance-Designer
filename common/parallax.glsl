
float ray_intersect_rm(    // use linear and binary search
	in sampler2D heightmap,
	in vec2 dp,
	in vec2 ds)
{
	const int linear_search_steps=200;
	const int binary_search_steps=50;

	// current size of search window
	float size = 1.0/float(linear_search_steps);
	// current depth position
	float depth = 0.0;
	// search front to back for first point inside object
	for( int i=0;i<linear_search_steps;i++ )
	{
		float t = texture2D(heightmap,dp+ds*depth).r;

		if (depth<(1.0-t))
			depth += size;
	}
	// recurse around first point (depth) for closest match
	for( int ii=0;ii<binary_search_steps;ii++ )
	{
		size*=0.5;
		float t = texture2D(heightmap,dp+ds*depth).r;
		if (depth<(1.0-t))
			depth += (2.0*size);
		depth -= size;
	}
	return depth;
}

vec2 updateUV(
	in sampler2D heightmap,
	in vec3 pointToCameraDirWS,
	in vec3 n,
	in vec3 t,
	in vec3 b,
	in float Depth,
	in vec2 uv,
	in vec2 uvScale,
	in float tiling)
{
	if (Depth > 0.0)
	{
		float a = dot(n,-pointToCameraDirWS);
		vec3 s = vec3(
			dot(pointToCameraDirWS,t),
			dot(pointToCameraDirWS,b),
			a);
		s *= Depth/a*0.1;
		vec2 ds = s.xy*uvScale;
		uv = uv*tiling*uvScale;
		float d = ray_intersect_rm(heightmap,uv,ds);
		return uv+ds*d;
	}
	else return uv*tiling;
}

