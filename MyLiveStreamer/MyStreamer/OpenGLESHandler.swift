//
//  OpenGLESHandler.swift
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/18.
//  Copyright © 2019 GevinChen. All rights reserved.
//

import UIKit
import CoreVideo
import AVFoundation
import VideoToolbox
import QuartzCore

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
let kColorConversion601:[GLfloat] = [
    1.164,  1.164, 1.164,
      0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
]

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
let kColorConversion601FullRange:[GLfloat] = [
    1.0,       1.0,    1.0,
    0.0,    -0.343,  1.765,
    1.4,    -0.711,    0.0,
]

// BT.709, which is the standard for HDTV.
let kColorConversion709:[GLfloat] = [
    1.164,  1.164, 1.164,
      0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
]

@objc class GLView: UIView {
    
    override class var layerClass: AnyClass {
        get {
            return CAEAGLLayer.self
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
}

@objc class OpenGLESHandler: NSObject {
    
    @objc var enableFilter = false
    @objc var glView: GLView?  
    @objc var eaglLayer:CAEAGLLayer?
    
    @objc var eaglContext: EAGLContext?
    @objc var framebufferSize: CGSize = CGSize.zero
    
    private var _yuvConvrtFramebuffer:GLuint = 0
    private var _yuvConvertPixelBuffer: CVPixelBuffer?
    private var _yuvConvertTextureRef: CVOpenGLESTexture?
    private var _yuvConvertTexture: GLuint = 0
    
    private var _pixellateFramebuffer:GLuint = 0
    private var _pixellatePixelBuffer: CVPixelBuffer?
    private var _pixellateTextureRef: CVOpenGLESTexture?
    private var _pixellateTexture: GLuint = 0
    
    private var _displayFramebuffer:GLuint = 0
    private var _colorRenderBuffer:GLuint = 0
    
    // vbo
    private var _vao: GLuint = 0
    private var _vbo: GLuint = 0
    
    private var _displayProgram: GLProgram?
    private var _yuvConvertProgram: GLProgram?
    private var _pixelateProgram: GLProgram?
    
    private var _coreVideoTextureCache: CVOpenGLESTextureCache?
    
    var luminanceTextureRef: CVOpenGLESTexture? = nil
    var chrominanceTextureRef: CVOpenGLESTexture? = nil

    private var _texture_yPlane: GLuint = 0
    private var _texture_uvPlane: GLuint = 0
    
    // shader variable id
    private var _uniform_y_texture: GLint = 0
    private var _uniform_uv_texture: GLint = 0
    private var _attr_textureCoord: GLint = 0
    private var _attr_squareVertices: GLint = 0
    private var _uniform_transformMatrix: GLint = 0
    private var _yuvTransformMatrix: [GLfloat] = kColorConversion601FullRange
    
    deinit {
        print("OpenGLESHandler dealloc")
    }
    
    override init() {
        super.init()
    }
    
    @objc
    func setupGL(framebufferSize: CGSize) {
        self.framebufferSize = framebufferSize
        self.setupGLContext()
        
        self.setupVAO()
        self.setupVideoTextureCache()
        
        self.setupDisplayFramebuffer()
        self.setupYuvConvertFramebuffer()
        self.setupPixellateFramebuffer()
        
        self.setupDisplayProgram()
        self.setupYUVConvertProgram()
        self.setupPixellateProgram()
    }

    func setupGLContext() {
        
        eaglLayer = glView?.layer as! CAEAGLLayer
        eaglLayer?.isOpaque = true
        eaglLayer?.drawableProperties = [ kEAGLDrawablePropertyRetainedBacking: NSNumber(value: false), // render 完後，要不要保留 render 資料，預設是不保留
                                          kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8 ]
        
        // 设置OpenGLES的版本为2.0 当然还可以选择1.0和最新的3.0的版本，以后我们会讲到2.0与3.0的差异，目前为了兼容性选择2.0的版本
        eaglContext = EAGLContext(api: EAGLRenderingAPI.openGLES2 )
        if eaglContext == nil {
            fatalError("Failed to initialize OpenGLES 2.0 context")
        }
        
        // 将当前上下文设置为我们创建的上下文
        guard EAGLContext.setCurrent(eaglContext) else {
            fatalError("Failed to set current OpenGL context")
        }
    }
    
    func setupVAO() {
        
        let vertices:[GLfloat] = [
            //  position      texture cooordinates
            -1.0, -1.0,    0.0, 0.0,
             1.0, -1.0,    1.0, 0.0,
            -1.0,  1.0,    0.0, 1.0,
             1.0,  1.0,    1.0, 1.0,
        ];
        
        // 建立 vao
        glGenVertexArrays(1, &_vao)
        glBindVertexArray(_vao)
        
        // 建立 vbo
        glGenBuffers(1, &_vbo);
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _vbo);
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<[GLfloat]>.size * vertices.count, vertices, GLenum(GL_STATIC_DRAW));
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0);
    }
    
    // MARK: - Framebuffer
    
    func setupVideoTextureCache() {
        if _coreVideoTextureCache == nil {
            // 建立 textureCache
            var result:CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, self.eaglContext!, nil, &_coreVideoTextureCache)
            if result != kCVReturnSuccess {
                fatalError( String(format:"Error at CVOpenGLESTextureCacheCreate %d", result))
            }
        }
    }
    
    func setupDisplayFramebuffer() {

        // 建立 renderbuffer
        glGenRenderbuffers(1, &_colorRenderBuffer);
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _colorRenderBuffer);
        
        // 把 layer 的 display buffer 配置給 render buffer
        eaglContext?.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer!)
        var backingWidth: GLint = 0
        var backingHeight: GLint = 0
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &backingWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &backingHeight)
        print("renderBuffer size: \(backingWidth), \(backingHeight)")
        
        glGenFramebuffers(1, &_displayFramebuffer);
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), _displayFramebuffer );
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), 
                                  GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER),
                                  _colorRenderBuffer);
        if (glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GL_FRAMEBUFFER_COMPLETE) {
            fatalError(String(format:"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))))
        }
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }
    
    func setupYuvConvertFramebuffer() {
        
        glGenFramebuffers(1, &_yuvConvrtFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), _yuvConvrtFramebuffer)
        
        // empty value for attr value.
        let empty : [NSObject:AnyObject] = [
            kCVPixelBufferCGImageCompatibilityKey : kCFTypeDictionaryValueCallBacks as AnyObject,
        ]
        
        let attrs : [NSObject:AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey : empty as AnyObject,
        ]
        
        // create render pixel buffer
        var result:CVReturn = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  Int(framebufferSize.width), 
                                                  Int(framebufferSize.height), 
                                                  kCVPixelFormatType_32BGRA, 
                                                  attrs as CFDictionary,
                                                  &_yuvConvertPixelBuffer)
        if result != kCVReturnSuccess {
            fatalError( String(format:"Error at CVPixelBufferCreate %d", result))
        }
        
        // textureCache + pixelBuffer > CVOpenGLESTexture
        result = CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault,
                                                               _coreVideoTextureCache!, // input CVOpenGLESTextureCache
                                                               _yuvConvertPixelBuffer!, // CVPixelBuffer
                                                               nil, // texture attributes
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RGBA, // internalFormat, opengl format，之後撈 _yuvConvertRenderPixelBuffer 的資料，就是 RGBA 這個排列
                                                               GLsizei(framebufferSize.width), 
                                                               GLsizei(framebufferSize.height),
                                                               GLenum(GL_BGRA), // format, native iOS format
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               0, // planeIndex
                                                               &_yuvConvertTextureRef) // output CVOpenGLESTextureCache
        if result != kCVReturnSuccess {
            fatalError( String(format:"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", result) )
        }
        
        _yuvConvertTexture = CVOpenGLESTextureGetName(_yuvConvertTextureRef!)
        glBindTexture(CVOpenGLESTextureGetTarget(_yuvConvertTextureRef!), CVOpenGLESTextureGetName(_yuvConvertTextureRef!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(_yuvConvertTextureRef!), 0);
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }
    
    func setupPixellateFramebuffer() {
        
        glGenFramebuffers(1, &_pixellateFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), _pixellateFramebuffer)
        
        // empty value for attr value.
        let empty : [NSObject:AnyObject] = [
            kCVPixelBufferCGImageCompatibilityKey : kCFTypeDictionaryValueCallBacks as AnyObject,
        ]
        
        let attrs : [NSObject:AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey : empty as AnyObject,
        ]
        
        /*
         
         注意CVPixelBufferCreate函数不支持 kCVPixelFormatType_32RGBA 等格式 不知道为什么。
         支持 kCVPixelFormatType_32ARGB 和 kCVPixelFormatType_32BGRA 等 
         iPhone为小端对齐，因此 kCVPixelFormatType_32ARGB 和 kCVPixelFormatType_32BGRA 都需要和 kCGBitmapByteOrder32Little 配合使用
         注意当 inputPixelFormat 为 kCVPixelFormatType_32BGRA 时，bitmapInfo不能是 kCGImageAlphaNone，kCGImageAlphaLast，kCGImageAlphaFirst，kCGImageAlphaOnly。
         注意 iPhone 的大小端对齐方式为小段对齐 可以使用宏 kCGBitmapByteOrder32Host 来解决大小端对齐 
         大小端对齐必须设置为 kCGBitmapByteOrder32Little。
         
         typedef CF_ENUM(uint32_t, CGImageAlphaInfo) {
            kCGImageAlphaNone,                For example, RGB.
            kCGImageAlphaPremultipliedLast,   For example, premultiplied RGBA
            kCGImageAlphaPremultipliedFirst,  For example, premultiplied ARGB
            kCGImageAlphaLast,                For example, non-premultiplied RGBA
            kCGImageAlphaFirst,               For example, non-premultiplied ARGB
            kCGImageAlphaNoneSkipLast,        For example, RBGX.
            kCGImageAlphaNoneSkipFirst,       For example, XRGB.
            kCGImageAlphaOnly                 No color data, alpha data only
         };
         
         CGBitmapInfo的设置
         uint32_t bitmapInfo = CGImageAlphaInfo | CGBitmapInfo;
         
         当 inputPixelFormat = kCVPixelFormatType_32BGRA
         CGBitmapInfo的正确的设置 只有如下两种正确设置
         uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
         uint32_t bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little;
  
         当 inputPixelFormat = kCVPixelFormatType_32ARGB
         CGBitmapInfo的正确的设置 只有如下两种正确设置
         uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Big;
         uint32_t bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Big;
          
         */
        
        // create render pixel buffer
        var result:CVReturn = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  Int(framebufferSize.width), 
                                                  Int(framebufferSize.height), 
                                                  kCVPixelFormatType_32BGRA, 
                                                  attrs as CFDictionary,
                                                  &_pixellatePixelBuffer)
        if result != kCVReturnSuccess {
            fatalError( String(format:"Error at CVPixelBufferCreate %d", result))
        }
        
        // textureCache + pixelBuffer > CVOpenGLESTexture
        result = CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault,
                                                               _coreVideoTextureCache!, // input CVOpenGLESTextureCache
                                                               _pixellatePixelBuffer!, // CVPixelBuffer
                                                               nil, // texture attributes
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RGBA, // internalFormat, opengl format
                                                               GLsizei(framebufferSize.width), 
                                                               GLsizei(framebufferSize.height),
                                                               GLenum(GL_BGRA), // format, native iOS format
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               0, // planeIndex
                                                               &_pixellateTextureRef) // output CVOpenGLESTextureCache
        if result != kCVReturnSuccess {
            fatalError( String(format:"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", result) )
        }
        
        _pixellateTexture = CVOpenGLESTextureGetName(_pixellateTextureRef!)
        glBindTexture(CVOpenGLESTextureGetTarget(_pixellateTextureRef!), CVOpenGLESTextureGetName(_pixellateTextureRef!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(_pixellateTextureRef!), 0);
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }
    
    @objc
    func destoryFrameBuffer() {
        glDeleteFramebuffers(1, &_yuvConvrtFramebuffer)
        glDeleteFramebuffers(1, &_displayFramebuffer)
        glDeleteFramebuffers(1, &_pixellateFramebuffer)
        _pixellateFramebuffer = 0
        _yuvConvrtFramebuffer = 0
        _displayFramebuffer = 0
        if _colorRenderBuffer != 0 {
            glDeleteRenderbuffers(1, &_colorRenderBuffer)
            self._colorRenderBuffer = 0
        }
        if _yuvConvertTexture != 0 {
            glDeleteTextures(1, &_yuvConvertTexture)
        }
        if _pixellateTexture != 0 {
            glDeleteTextures(1, &_pixellateTexture)
        }
    }
    
    // MARK: - Program
    
    func setupYUVConvertProgram() {
 
        let vertPath = Bundle.main.path(forResource: "yuvConvertShader", ofType: "vsh")!
        let vertShaderString = try! String(contentsOfFile: vertPath)
        let fragPath = Bundle.main.path(forResource: "yuvConvertShader", ofType: "fsh")!
        let fragShaderString = try! String(contentsOfFile: fragPath)
        
        //加载shader
        self._yuvConvertProgram = GLProgram(vertexShaderString: vertShaderString, fragmentShaderString: fragShaderString)
        // init attributes, should before link()
        self._yuvConvertProgram?.addAttribute(attrName: "position")
        self._yuvConvertProgram?.addAttribute(attrName: "inputTextureCoordinate")

        let status = self._yuvConvertProgram?.link()
        if status == false {
            let progLog = self._yuvConvertProgram?.programLog ?? ""
            NSLog("Program link log: %@", progLog)
            let vertLog = self._yuvConvertProgram?.vertShaderLog ?? ""
            NSLog("Vertex shader compile log: %@", vertLog)
            let fragLog = self._yuvConvertProgram?.fragShaderLog ?? ""
            NSLog("Fragment shader compile log: %@", fragLog)
            self._yuvConvertProgram = nil
            fatalError("Filter shader link failed")
        }
        //self._yuvConvertProgram.use()
    }
    
    func setupPixellateProgram() {
        
        let vertPath = Bundle.main.path(forResource: "PixellateShader", ofType: "vsh")!
        let vertShaderString = try! String(contentsOfFile: vertPath)
        let fragPath = Bundle.main.path(forResource: "PixellateShader", ofType: "fsh")!
        let fragShaderString = try! String(contentsOfFile: fragPath)
        
        //加载shader
        self._pixelateProgram = GLProgram(vertexShaderString: vertShaderString, fragmentShaderString: fragShaderString)
        // init attributes, should before link()
        self._pixelateProgram?.addAttribute(attrName: "position")
        self._pixelateProgram?.addAttribute(attrName: "inputTextureCoordinate")
        
        let status = self._pixelateProgram?.link()
        if status == false {
            let progLog = self._pixelateProgram?.programLog ?? ""
            NSLog("Program link log: %@", progLog)
            let vertLog = self._pixelateProgram?.vertShaderLog ?? ""
            NSLog("Vertex shader compile log: %@", vertLog)
            let fragLog = self._pixelateProgram?.fragShaderLog ?? ""
            NSLog("Fragment shader compile log: %@", fragLog)
            self._pixelateProgram = nil
            fatalError("Filter shader link failed")
        }
    }
    
    func setupDisplayProgram() {
        
        let vertPath = Bundle.main.path(forResource: "DisplayShader", ofType: "vsh")!
        let vertShaderString = try! String(contentsOfFile: vertPath)
        let fragPath = Bundle.main.path(forResource: "DisplayShader", ofType: "fsh")!
        let fragShaderString = try! String(contentsOfFile: fragPath)
        
        //加载shader
        self._displayProgram = GLProgram(vertexShaderString: vertShaderString, fragmentShaderString: fragShaderString)
        // init attributes, should before link()
        self._displayProgram?.addAttribute(attrName: "position")
        self._displayProgram?.addAttribute(attrName: "inputTextureCoordinate")
        
        let status = self._displayProgram?.link()
        if status == false {
            let progLog = self._displayProgram?.programLog ?? ""
            NSLog("Program link log: %@", progLog)
            let vertLog = self._displayProgram?.vertShaderLog ?? ""
            NSLog("Vertex shader compile log: %@", vertLog)
            let fragLog = self._displayProgram?.fragShaderLog ?? ""
            NSLog("Fragment shader compile log: %@", fragLog)
            self._displayProgram = nil
            fatalError("Filter shader link failed")
        }
    }
    
    // MARK: - Draw
    
    func performYUVConvert() {
        
        self._yuvConvertProgram?.use()
        
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _vbo)
        let positionPtr = UnsafeRawPointer(bitPattern: 0)
        let textcoordsPtr = UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 2 )
        let positionIndex = self._yuvConvertProgram?.attributeLocation(name: "position")
        glVertexAttribPointer( positionIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE),  GLsizei(MemoryLayout<GLfloat>.size * 4), positionPtr)
        glEnableVertexAttribArray(positionIndex!)
        
        let textureCoordsIndex = self._yuvConvertProgram?.attributeLocation(name: "inputTextureCoordinate") 
        glVertexAttribPointer( textureCoordsIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<GLfloat>.size * 4), textcoordsPtr)
        glEnableVertexAttribArray(textureCoordsIndex!)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glUniform1i(GLint(self._yuvConvertProgram!.uniformLocation(name: "yTexture")), 4)
        glUniform1i(GLint(self._yuvConvertProgram!.uniformLocation(name: "uvTexture")), 5)
        glUniformMatrix3fv(GLint(self._yuvConvertProgram!.uniformLocation(name: "yuvConversionMatrix")), 1, GLboolean(GL_FALSE), self._yuvTransformMatrix)
        
        self.drawOnBuffer(framebuffer: self._yuvConvrtFramebuffer)
    }
    
    func performPixellate() {
        
        self._pixelateProgram?.use()
        
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), _vbo)
        let positionPtr = UnsafeRawPointer(bitPattern: 0)
        let textcoordsPtr = UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 2 )
        let positionIndex = self._pixelateProgram?.attributeLocation(name: "position")
        glVertexAttribPointer( positionIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE),  GLsizei(MemoryLayout<GLfloat>.size * 4), positionPtr)
        glEnableVertexAttribArray(positionIndex!)
        
        let textureCoordsIndex = self._pixelateProgram?.attributeLocation(name: "inputTextureCoordinate") 
        glVertexAttribPointer( textureCoordsIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<GLfloat>.size * 4), textcoordsPtr)
        glEnableVertexAttribArray(textureCoordsIndex!)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glActiveTexture(GLenum(GL_TEXTURE2))
        glBindTexture(GLenum(GL_TEXTURE_2D), self._yuvConvertTexture)
        glUniform1i(GLint(self._pixelateProgram!.uniformLocation(name: "inputImageTexture")), 2)
        glUniform1f(GLint(self._pixelateProgram!.uniformLocation(name: "fractionalWidthOfPixel")), 0.05)
        glUniform1f(GLint(self._pixelateProgram!.uniformLocation(name: "aspectRatio")), GLfloat(framebufferSize.height/framebufferSize.width))
        
        self.drawOnBuffer(framebuffer: self._pixellateFramebuffer)

    }
    
    func transformVertices( drawRect: CGRect ) -> [GLfloat] {
        let viewSize = self.eaglLayer!.bounds.size
        let originX:GLfloat = GLfloat(-1.0 + (2.0 * (drawRect.origin.x/viewSize.width)) )
        let originY:GLfloat = GLfloat(-1.0 + (2.0 * (drawRect.origin.y/viewSize.height)) )
        let width = 2.0 * GLfloat(drawRect.width/viewSize.width)
        let height = 2.0 * GLfloat(drawRect.height/viewSize.height) 
        // -1 ~ 1 代表整個寬高的normalize，0代表中心，所以整個寬的比例是 2.0
        /*.
         The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
         Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively, covers the entire screen.
         */
        
        let vertices: [GLfloat] = [
            originX         , originY         ,// 左下
            originX + width , originY         ,// 右下
            originX         , originY + height,// 左上
            originX + width , originY + height,// 右上
        ]
        return vertices
    }

    func displayLayer( renderTexture: GLuint) {
        
        self._displayProgram?.use()

        let vertices = self.transformVertices(drawRect: CGRect(x: 0, y: 0, width: self.eaglLayer!.bounds.size.width/2, height: self.eaglLayer!.bounds.size.height/2))

        let textCoords: [GLfloat] = [ // 正常坐标
            0, 0,
            1, 0,
            0, 1,
            1, 1,
        ]
        
        let positionIndex = self._displayProgram?.attributeLocation(name: "position")
        glVertexAttribPointer( positionIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, vertices)
        glEnableVertexAttribArray(positionIndex!)
        
        let textureCoordsIndex = self._displayProgram?.attributeLocation(name: "inputTextureCoordinate") 
        glVertexAttribPointer( textureCoordsIndex!, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, textCoords)
        glEnableVertexAttribArray(textureCoordsIndex!)
//        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), renderTexture)
        self._displayProgram?.setUniformi(uniformName: "inputImageTexture", integer1: 1)
        
        //self.drawOnBuffer(framebuffer: self._displayFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), _displayFramebuffer)
        
        glViewport(0, 0, GLsizei(framebufferSize.width), GLsizei(framebufferSize.height) );
        
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT));
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4);
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        
        // display renderbuffer
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _colorRenderBuffer)
        self.eaglContext?.presentRenderbuffer(Int(GL_RENDERBUFFER))
        
    }
    
    func drawOnBuffer(framebuffer: GLuint) {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        
        glBindVertexArray(_vao)
        
        glViewport(0, 0, GLsizei(framebufferSize.width), GLsizei(framebufferSize.height) );
        
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT));
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4);
        
        glBindVertexArray(0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }
    
    // MARK: - Handle SampleBuffer
            
    @objc
    func processingVideoSampleBuffer(sampleBuffer: CMSampleBuffer, isFullYUVRange: Bool) {
        
        guard let cameraFrame: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("fail to get ImageBuffer.")
            return
        }

        let bufferWidth:Int = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight:Int = CVPixelBufferGetHeight(cameraFrame)

        // Periodic texture cache flush every frame
        luminanceTextureRef = nil
        chrominanceTextureRef = nil
        CVOpenGLESTextureCacheFlush(_coreVideoTextureCache!, 0)
        
        if EAGLContext.current() != self.eaglContext {
            EAGLContext.setCurrent(self.eaglContext) // 非常重要的一行代码
        }
//        let startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
//        let currentTime: CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let colorAttachments:Unmanaged<CFTypeRef> = CVBufferGetAttachment(cameraFrame, kCVImageBufferYCbCrMatrixKey, nil)!
        
        let value = Unmanaged.fromOpaque(colorAttachments.toOpaque()).takeUnretainedValue() as CFString
        if(CFStringCompare(value, kCVImageBufferYCbCrMatrix_ITU_R_601_4, CFStringCompareFlags.compareCaseInsensitive) == CFComparisonResult.compareEqualTo) {
            if (isFullYUVRange) {
                _yuvTransformMatrix = kColorConversion601FullRange;
            } else {
                _yuvTransformMatrix = kColorConversion601;
            }
        } else {
            _yuvTransformMatrix = kColorConversion709;
        }
    
        guard CVPixelBufferGetPlaneCount(cameraFrame) > 0 else {
            print("camera frame plane count is 0.")
            return
        } 
        
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags.readOnly )
        
        if (self.framebufferSize.width != CGFloat(bufferWidth)) && (self.framebufferSize.height != CGFloat(bufferHeight)) {
            self.framebufferSize = CGSize(width: bufferWidth, height: bufferHeight)
        }
        
        var err: CVReturn = -1
        // Y-plane
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, 
                                                           _coreVideoTextureCache!, 
                                                           cameraFrame,
                                                           nil,
                                                           GLenum(GL_TEXTURE_2D),
                                                           GL_LUMINANCE,
                                                           GLsizei(bufferWidth), 
                                                           GLsizei(bufferHeight),
                                                           GLenum(GL_LUMINANCE),
                                                           GLenum(GL_UNSIGNED_BYTE),
                                                           0,
                                                           &luminanceTextureRef)
        if err != kCVReturnSuccess {
            NSLog("Error at CVOpenGLESTextureCacheCreateTextureFromImage y-channel %d", err);
        }
        glEnable(GLenum(GL_TEXTURE_2D))
        glActiveTexture(GLenum(GL_TEXTURE4))
        //self._texture_yPlane = CVOpenGLESTextureGetName(luminanceTextureRef!)
        glBindTexture(CVOpenGLESTextureGetTarget(luminanceTextureRef!), CVOpenGLESTextureGetName(luminanceTextureRef!))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR);
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR);
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        
        // UV-plane
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, 
                                                           _coreVideoTextureCache!, 
                                                           cameraFrame, 
                                                           nil, 
                                                           GLenum(GL_TEXTURE_2D),
                                                           GL_LUMINANCE_ALPHA, 
                                                           GLsizei(bufferWidth/2), 
                                                           GLsizei(bufferHeight/2),
                                                           GLenum(GL_LUMINANCE_ALPHA), 
                                                           GLenum(GL_UNSIGNED_BYTE),
                                                           1,
                                                           &chrominanceTextureRef);
        if err != kCVReturnSuccess {
            NSLog("Error at CVOpenGLESTextureCacheCreateTextureFromImage uv-channel %d", err)
        }

        glActiveTexture(GLenum(GL_TEXTURE5))
        //self._texture_uvPlane = CVOpenGLESTextureGetName(chrominanceTextureRef!)
        glBindTexture(CVOpenGLESTextureGetTarget(chrominanceTextureRef!), CVOpenGLESTextureGetName(chrominanceTextureRef!))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR);
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR);
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        
        // yuv convert to rgba
        self.performYUVConvert()
        // display renderbuffer
        if self.enableFilter {
            // pixellate filter
            self.performPixellate()
            self.displayLayer(renderTexture: _pixellateTexture)
        } else {
            self.displayLayer(renderTexture: _yuvConvertTexture)
        } 
        
        // rgb 轉 i420
        
        // publish to rtmp server
        CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags.readOnly);
       
    }
    
    // MARK: - Read Buffer
    
    @objc
    func getYUVConvertPixelBuffer() -> CVPixelBuffer? {
        return _yuvConvertPixelBuffer
    } 
    
    @objc
    func getPixellatePixelBuffer() -> CVPixelBuffer? {
        return _pixellatePixelBuffer
    } 
    
    @objc
    func getBufferBytes() -> UnsafeMutableRawPointer? {
        guard let pixelBuffer = _pixellatePixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        let bufferBytes: UnsafeMutableRawPointer? = CVPixelBufferGetBaseAddress(pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        return bufferBytes 
    }

    @objc
    func getBufferImage() -> UIImage? {
        // 換 _yuvConvertRenderPixelBuffer 這個就看未執行濾鏡的畫面
        guard let pixelBuffer = _pixellatePixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        let width = CVPixelBufferGetWidth( pixelBuffer )
        let height = CVPixelBufferGetHeight( pixelBuffer )
        let bytesPerRow = CVPixelBufferGetBytesPerRow( pixelBuffer )
        let bufferSize = CVPixelBufferGetDataSize(pixelBuffer);
        let bufferBytes: UnsafeMutableRawPointer? = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        UIGraphicsBeginImageContext(CGSize(width: width, height: height))
        guard let cgContext: CGContext = UIGraphicsGetCurrentContext() else {
            print("UIGraphicsGetCurrentContext fail.")
            return nil
        }
        
        guard var pData_dst = cgContext.data?.assumingMemoryBound(to: UInt8.self) else {
            print("get CGContext data fail.")
            return nil
        }
        
        // void* 轉成 UInt8*
        guard let pData_src = bufferBytes?.assumingMemoryBound(to: UInt8.self) else {
            print("convert pointer type fail.")
            return nil
        }
        let dst_stride = cgContext.bytesPerRow
        
        for y in 0..<height {
            for x in 0..<width {
                let offsetDst = (dst_stride * y) + (4*x) 
                let offsetSrc = (bytesPerRow * y) + (4*x)
                pData_dst.advanced(by: offsetDst).pointee   = pData_src.advanced(by: offsetSrc  ).pointee // R 
                pData_dst.advanced(by: offsetDst+1).pointee = pData_src.advanced(by: offsetSrc+1).pointee // G
                pData_dst.advanced(by: offsetDst+2).pointee = pData_src.advanced(by: offsetSrc+2).pointee // B
                pData_dst.advanced(by: offsetDst+3).pointee = pData_src.advanced(by: offsetSrc+3).pointee // A
            }
        }
        guard let image: UIImage = UIGraphicsGetImageFromCurrentImageContext() else {
            print("create image fail.")
            return nil
        } 
        UIGraphicsEndImageContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        return image
    }

}
