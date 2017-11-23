/////////////////////////////////// Control shader    
 
#version 400 core
#extension GL_ARB_tessellation_shader : enable

layout(vertices = 3) out;

in vec4 oVS_Normal[];
in vec2 oVS_UV[];
in vec4 oVS_Tangent[];
in vec4 oVS_Binormal[];

out vec4 oTCS_Normal[];
out vec2 oTCS_UV[];
out vec4 oTCS_Tangent[];
out vec4 oTCS_Binormal[];

uniform float tessellationFactor;

void main()
{
   gl_TessLevelOuter[0] = tessellationFactor;
   gl_TessLevelOuter[1] = tessellationFactor;
   gl_TessLevelOuter[2] = tessellationFactor;
   gl_TessLevelInner[0] = tessellationFactor;
   gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position;

   oTCS_Normal[gl_InvocationID]     = oVS_Normal[gl_InvocationID];
   oTCS_UV[gl_InvocationID]         = oVS_UV[gl_InvocationID];
   oTCS_Tangent[gl_InvocationID]    = oVS_Tangent[gl_InvocationID];
   oTCS_Binormal[gl_InvocationID]   = oVS_Binormal[gl_InvocationID];
}
