varying highp vec2 textureCoordinate;

uniform sampler2D yTexture; //luminanceTexture;
uniform sampler2D uvTexture; //chrominanceTexture;
uniform mediump mat3 yuvConversionMatrix;

void main()
{
    mediump vec3 yuv;
    lowp vec3 rgb;
    
    yuv.x = texture2D(yTexture, textureCoordinate).r;
    yuv.yz = texture2D(uvTexture, textureCoordinate).ra - vec2(0.5, 0.5);
    rgb = yuvConversionMatrix * yuv;
    
    gl_FragColor = vec4(rgb, 1);
}
