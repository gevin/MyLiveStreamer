
varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;

uniform highp float fractionalWidthOfPixel; // 馬賽克格子的大小，0~1，以 texture.width 為比例
uniform highp float aspectRatio; // 寬高比例 高/寬

void main()
{
    highp vec2 sampleDivisor = vec2(fractionalWidthOfPixel, fractionalWidthOfPixel / aspectRatio);
    
    highp vec2 samplePos = textureCoordinate - mod(textureCoordinate, sampleDivisor) + 0.5 * sampleDivisor;
    gl_FragColor = texture2D(inputImageTexture, samplePos );
}
