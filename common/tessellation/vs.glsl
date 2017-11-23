/////////////////////////////// Vertex shader
#version 120

attribute vec4 iVS_Position;
attribute vec4 iVS_Normal;
attribute vec2 iVS_UV;
attribute vec4 iVS_Tangent;
attribute vec4 iVS_Binormal;

varying vec4 oVS_Normal;
varying vec2 oVS_UV;
varying vec4 oVS_Tangent;
varying vec4 oVS_Binormal;

void main()
{
    gl_Position = iVS_Position;
    oVS_Normal = iVS_Normal;
    oVS_UV = iVS_UV;
    oVS_Tangent = iVS_Tangent;
    oVS_Binormal = iVS_Binormal;
}
