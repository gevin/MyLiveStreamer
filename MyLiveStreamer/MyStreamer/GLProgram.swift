//
//  GLProgram.swift
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/18.
//  Copyright © 2019 GevinChen. All rights reserved.
//

import UIKit

class GLProgram: NSObject {
    
    private var _attributes:[String] = []
    private var _uniforms:[String: Int32] = [:]
    
    var program: GLuint = 0
    private var _vertShader: GLuint = 0
    private var _fragShader: GLuint = 0
    var vertShaderLog: String = ""
    var fragShaderLog: String = ""
    var programLog: String = ""
    
    init( vertexShaderString: String, fragmentShaderString: String ) {
        super.init()
        
        self.program = glCreateProgram()
        
        _vertShader = self.compileShader( type:GLenum(GL_VERTEX_SHADER), shaderString:vertexShaderString )
        if _vertShader == 0 {
            NSLog("Failed to compile vertex shader");
        }
        
        _fragShader = self.compileShader( type:GLenum(GL_FRAGMENT_SHADER), shaderString:fragmentShaderString )
        if _fragShader == 0 {
            NSLog("Failed to compile fragment shader");
        }
        
        glAttachShader( self.program, _vertShader);
        glAttachShader( self.program, _fragShader);

    }
    
    // START:compile
    func compileShader( type: GLenum, shaderString: String ) -> GLuint {
    
        var status:GLint = 0
        var shader: GLuint = 0 
        shader = glCreateShader(type)
        let shaderStringUTF8 = shaderString.cString(using: String.Encoding.utf8)
        var shaderStringPtr =  UnsafePointer(shaderStringUTF8)
        glShaderSource(shader, 1, &shaderStringPtr, nil);
        glCompileShader(shader);
    
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
    
        if (status != GL_TRUE) {
            var logLength: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength);
            
            if (logLength > 0) {
                let log = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
                glGetShaderInfoLog(shader, logLength, &logLength, log)
                if type == GL_VERTEX_SHADER {
                    self.vertShaderLog = String(format:"%s", log) 
                }
                if type == GL_FRAGMENT_SHADER {
                    self.fragShaderLog = String(format:"%s", log)
                }
                log.deallocate()
            }
            return 0
        }    
    
    //    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
    //    NSLog(@"Compiled in %f ms", linkTime * 1000.0);
    
        return shader
    }
    
    func link() -> Bool {
        //    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
        
        var status: GLint = 0
        
        glLinkProgram(self.program)
        
        glGetProgramiv(self.program, GLenum(GL_LINK_STATUS), &status);
        if status == GL_FALSE {
            return false
        }
        
        if self._vertShader != 0 {
            glDeleteShader(self._vertShader)
            self._vertShader = 0
        }
        if _fragShader != 0 {
            glDeleteShader(_fragShader)
            _fragShader = 0
        }
        
//        self.initialized = false
        
        //    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
        //    NSLog(@"Linked in %f ms", linkTime * 1000.0);
        
        return true
    }
    
    func validate()  {
        var logLength: GLint = 0
        
        glValidateProgram(self.program)
        glGetProgramiv(self.program, GLenum(GL_INFO_LOG_LENGTH), &logLength);
        if (logLength > 0) {
            let log = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
            glGetProgramInfoLog(self.program, logLength, &logLength, log)
            self.programLog = String(format:"%s", log)
            log.deallocate()
        }    
    }
    
    func use() {
        glUseProgram(self.program)
    }
    
    func addAttribute( attrName: String ) {
        if !self._attributes.contains(attrName) {
            self._attributes.append(attrName)
            let attrNameUTF8 = attrName.cString(using: String.Encoding.utf8)
            let attrNamePtr =  UnsafePointer(attrNameUTF8)
            guard let index = self._attributes.firstIndex(of: attrName) else {
                fatalError("\(attrName) did not exist.")
            }
            glBindAttribLocation(self.program, GLuint(index), attrNamePtr)
        }
    }
    
    func attributeLocation( name: String ) -> GLuint {
        guard let index = self._attributes.firstIndex(of: name) else {
            fatalError("\(name) did not exist.")
        }
        return GLuint(index)
    }
        
    func uniformLocation( name: String ) -> GLuint {
        if let index = self._uniforms[name] {
            return GLuint(index)
        } else {
            let uniformNameUTF8 = name.cString(using: String.Encoding.utf8)
            let uniformNamePtr =  UnsafePointer(uniformNameUTF8)
            let uniformIndex = glGetUniformLocation(self.program, uniformNamePtr)
            self._uniforms[name] = uniformIndex
            return GLuint(uniformIndex)
        }
    }
    
    func setAttribute( attrName: String, oneElementSize: GLint, dataType: GLenum, normalized: GLboolean, stride: GLsizei, ptr: UnsafeRawPointer?) {
        let attrIndex = self.attributeLocation(name: attrName)
        glVertexAttribPointer(attrIndex, oneElementSize, dataType, normalized, stride, ptr);
        glEnableVertexAttribArray(attrIndex);
    }
    
    // 二個輸入以上，通常是 vec2, vec3, vec4
    func setUniformi( uniformName: String, integer1: GLint, integer2: GLint? = nil, integer3: GLint? = nil, integer4: GLint? = nil ) {
        let location = self.uniformLocation(name: uniformName)
        if let int_y = integer2, let int_z = integer3, let int_w = integer4 {
            glUniform4i(GLint(location), integer1, int_y, int_z, int_w)
        }  
        else if let int_y = integer2, let int_z = integer3 {
            glUniform3i(GLint(location), integer1, int_y, int_z)
        }
        else if let int_y = integer2 {
            glUniform2i(GLint(location), integer1, int_y)
        }
        else {
            glUniform1i(GLint(location), integer1)
        }
    }
    
    // 二個輸入以上，通常是 vec2, vec3, vec4
    func setUniformf( uniformName: String, float1: GLfloat, float2: GLfloat? = nil, float3: GLfloat? = nil, float4: GLfloat? = nil ) {
        let location = self.uniformLocation(name: uniformName)
        if let float_y = float2, let float_z = float3, let float_w = float4 {
            glUniform4f(GLint(location), float1, float_y, float_z, float_w)
        }  
        else if let float_y = float2, let float_z = float3 {
            glUniform3f(GLint(location), float1, float_y, float_z)
        }
        else if let float_y = float2 {
            glUniform2f(GLint(location), float1, float_y)
        }
        else {
            glUniform1f(GLint(location), float1)
        }
    }
    
    // matrix GLKMatrix4
    func setUniformMatrix( uniformName: String, dimW: Int, dimH: Int, matrixPtr: UnsafePointer<GLfloat>) {
        let location = self.uniformLocation(name: uniformName)
        
        switch (dimW, dimH) {
        case (4,4):
            glUniformMatrix4fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (3,3):
            glUniformMatrix3fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (2,2):
            glUniformMatrix2fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (2,3):
            glUniformMatrix2x3fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (2,4):
            glUniformMatrix2x4fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (3,2):
            glUniformMatrix3x2fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (3,4):
            glUniformMatrix3x4fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (4,3):
            glUniformMatrix4x3fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        case (4,2):
            glUniformMatrix4x2fv(GLint(location), 1, GLboolean(GL_FALSE), matrixPtr)
        default:
            break
        }
        
    }
    
    func destroy() {
        if self._vertShader != 0 {
            glDeleteShader(self._vertShader)
        }
        
        if _fragShader != 0 {
            glDeleteShader(_fragShader)
        }
        
        if self.program != 0 {
            glDeleteProgram(self.program)
        }
    }
}
