import cython

from posix cimport fcntl,unistd, stat, time
from posix.ioctl cimport ioctl
from libc.errno cimport errno,EINTR,EINVAL,EAGAIN,EIO
from libc.string cimport strerror
cimport cmman as mman
cimport cselect as select
cimport cv4l2 as v4l2
cimport cturbojpeg as turbojpeg
# cimport cv4lconvert as v4lconvert
cimport numpy as np
import numpy as np


#logging
import logging
logger = logging.getLogger(__name__)

def fourcc_string(i):
    s = chr(i & 255)
    for shift in (8,16,24):
        s += chr(i>>shift & 255)
    return s

cpdef v4l2.__u32 fourcc_u32(char * fourcc):
    return v4l2.v4l2_fourcc(fourcc[0],fourcc[1],fourcc[2],fourcc[3])


cdef class buffer_handle:
    cdef void *start
    cdef size_t length

    def __repr__(self):
        return  "Buffer pointing to %s. length: %s"%(<int>self.start,self.length)
      

    
cdef class Frame:
    '''
    The Frame Object holds image data and image metadata.

    The Frame object is returned from Capture.get_frame()

    It will hold the data in the transport format the Capture is configured to grab.
    Usually this is mjpeg or yuyv

    Other formats can be requested and will be converted/decoded on the fly.
    Frame will use caching to avoid redunant work.
    Usually RGB8,YUYV or GRAY are requested formats.

    WARNING:
    When capture.get_frame() is called again previos instances of Frame will point to invalid memory.
    Specifically the image format in the capture transport format.
    Previously converted formats are still valid.
    '''

    cdef turbojpeg.tjhandle tj_context
    cdef buffer_handle _jpeg_buffer
    cdef unsigned char[:] _bgr_buffer, _gray_buffer,_yuv_buffer #we use numpy for memory management.
    cdef bint _yuv_converted, _bgr_converted
    cdef public double timestamp
    cdef public int width,height, yuv_subsampling

    def __cinit__(self):
        # pass        
        # self._jpeg_buffer.start = NULL doing this leads to the very strange behaivour of numpy slicing to break!
        self._yuv_converted = False
        self._bgr_converted = False
    def __init__(self):
        pass


    property jpeg_buffer:
        def __set__(self,buffer_handle new_buffer):
            self._jpeg_buffer = new_buffer

        def __get__(self):
            #retuns buffer handle to jpeg buffer
            if self._jpeg_buffer.start == NULL:
                raise Exception("jpeg buffer not used and not allocated.")
            return self._jpeg_buffer


    property yuv422_buffer:
        def __set__(self,buffer_handle new_buffer):
            raise Exception('Read only')

        def __get__(self):
            #retuns buffer handle to yuv422 buffer
            if self._yuv_converted == False:
                if self._jpeg_buffer.start != NULL:
                    self.jpeg2yuv()
                else:
                    raise Exception("No source image data found to convert from.")
            cdef buffer_handle buf = buffer_handle()
            buf.start = <void*>(&self._yuv_buffer[0])
            buf.length = self._yuv_buffer.shape[0]
            return buf


    property yuv:
        def __set__(self,val):
            raise Exception('read only')
        def __get__(self):
            '''
            planar YUV420 returned in 3 numpy arrays:
            420 subsampling:
                Y(height,width) U(height/2,width/2), V(height/2,width/2)
            '''
            if self._yuv_converted is False:
                if self._jpeg_buffer.start != NULL:
                    self.jpeg2yuv()
                else:
                    raise Exception("No source image data found to convert from.")

            cdef np.ndarray[np.uint8_t, ndim=2] Y,U,V
            y_plane_len = self.width*self.height
            Y = np.asarray(self._yuv_buffer[:y_plane_len]).reshape(self.height,self.width)

            uv_plane_len = y_plane_len/2
            offset = y_plane_len
            U = np.asarray(self._yuv_buffer[offset:offset+uv_plane_len]).reshape(self.height,self.width/2)
            offset += uv_plane_len
            V = np.asarray(self._yuv_buffer[offset:offset+uv_plane_len]).reshape(self.height,self.width/2)


            #hack solution to go from YUV422 to YUV420
            U = U[::2,:]
            V = V[::2,:]
            return Y,U,V

    property gray:      
        def __set__(self,val):
            raise Exception('read only')
        def __get__(self):
            # return gray aka luminace plane of YUV image.
            if self._yuv_array is None:
                if self._jpeg_buffer.start != NULL:
                    self.jpeg2yuv()
                else:
                    raise Exception("No source image data found to convert from.")
            cdef np.ndarray[np.uint8_t, ndim=2] Y
            Y = np.asarray(self._yuv_buffer[:self.width*self.height]).reshape(self.height,self.width)
            return Y



    property bgr:      
        def __set__(self,val):
            raise Exception('read only')
        def __get__(self):
            if self._bgr_converted is False:
                #toggle conversion if needed
                _ = self.yuv
                self.yuv2bgr()

            cdef np.ndarray[np.uint8_t, ndim=3] BGR
            BGR = np.asarray(self._bgr_buffer).reshape(self.height,self.width,3)
            return BGR


    #for legacy reasons.
    property img:      
        def __set__(self,val):
            raise Exception('read only')
        def __get__(self):
            return self.bgr



    cdef yuv2bgr(self):
        #2.75 ms at 1080p
        cdef int channels = 3
        cdef int result
        self._bgr_buffer = np.empty(self.width*self.height*channels, dtype=np.uint8)
        result = turbojpeg.tjDecodeYUV(self.tj_context, &self._yuv_buffer[0], 4, turbojpeg.TJSAMP_422, 
                                        &self._bgr_buffer[0], self.width, 0, self.height, turbojpeg.TJPF_BGR, 0)
        if result == -1:
            logger.error('Turbojpeg yuv2bgr error: %s'%turbojpeg.tjGetErrorStr() )
        self._bgr_converted = True



    cdef jpeg2yuv(self):
        # 7.55 ms on 1080p
        cdef int channels = 1
        cdef int jpegSubsamp, j_width,j_height
        cdef int result

        turbojpeg.tjDecompressHeader2(self.tj_context,  <unsigned char *>self._jpeg_buffer.start, 
                                        self._jpeg_buffer.length, 
                                        &j_width, &j_height, &jpegSubsamp)

        self._yuv_buffer = np.empty(turbojpeg.tjBufSizeYUV2(j_width,2, j_height, jpegSubsamp), dtype=np.uint8)

        result =  turbojpeg.tjDecompressToYUV(self.tj_context, 
                                             <unsigned char *>self._jpeg_buffer.start, 
                                             self._jpeg_buffer.length,
                                             &self._yuv_buffer[0],
                                              0)
        if result == -1:
            logger.error('Turbojpeg jpeg2yuv error: %s'%turbojpeg.tjGetErrorStr() )
        self.yuv_subsampling = jpegSubsamp
        self._yuv_converted = True
    # cdef jpeg2bgr(self):
    #     #10.66ms on 1080p
    #     cdef int channels = 3
    #     cdef int jpegSubsamp, j_width,j_height
    #     cdef int result
    #     cdef np.ndarray[np.uint8_t, ndim=1] bgr_array = np.empty(self.width*self.height*channels, dtype=np.uint8)
    #     turbojpeg.tjDecompressHeader2(self.tj_context,  <unsigned char *>self._jpeg_buffer.start, self._jpeg_buffer.length, &j_width, &j_height, &jpegSubsamp)
    #     result = turbojpeg.tjDecompress2(self.tj_context, <unsigned char *>self._jpeg_buffer.start, self._jpeg_buffer.length, 
    #                             <unsigned char *> bgr_array.data, 
    #                             j_width, 0, j_height, turbojpeg.TJPF_BGR, 0)#turbojpeg.TJFLAG_FASTDCT
    #     if result == -1:
    #         logger.error('Turbojpeg jpeg2bgr error: %s'%turbojpeg.tjGetErrorStr() )
    #     self._bgr_array = bgr_array
    #     self._bgr_array.shape = self.height,self.width,channels


    # cdef jpeg2gray(self):
    #     #6.02ms on 1080p
    #     cdef int channels = 1
    #     cdef int jpegSubsamp, j_width,j_height
    #     cdef int result
    #     cdef np.ndarray[np.uint8_t, ndim=1] array = np.empty(self.width*self.height*channels, dtype=np.uint8)
    #     turbojpeg.tjDecompressHeader2(self.tj_context,  <unsigned char *>self._jpeg_buffer.start, self._jpeg_buffer.length, &j_width, &j_height, &jpegSubsamp)
    #     result = turbojpeg.tjDecompress2(self.tj_context, <unsigned char *>self._jpeg_buffer.start, self._jpeg_buffer.length, 
    #                             <unsigned char *> array.data, 
    #                             j_width, 0, j_height, turbojpeg.TJPF_GRAY, 0)#turbojpeg.TJFLAG_FASTDCT

    #     if result == -1:
    #         logger.error('Turbojpeg jpeg2gray error: %s'%turbojpeg.tjGetErrorStr() )
    #     self._gray_array = array
    #     self._gray_array.shape = self.height,self.width

    def clear_caches(self):
        self._bgr_converted = False
        self._yuv_converted = False





cdef class Capture:
    """
    Video Capture class.
    A Class giving access to a capture devices using the v4l2 provides drivers and userspace API.
    The intent is to always grab mjpeg frames and give access to theses buffer using the Frame class.

    All controls are exposed and can be enumerated using the controls list.
    """
    cdef int dev_handle 
    cdef char *dev_name
    cdef bint _camera_streaming, _buffers_initialized
    cdef object _transport_formats, _frame_rates,_frame_sizes
    cdef object  _frame_rate, _frame_size # (rate_num,rate_den), (width,height)
    cdef v4l2.__u32 _transport_format

    cdef bint _buffer_active
    cdef int _allocated_buf_n
    cdef v4l2.v4l2_buffer _active_buffer
    cdef list buffers

    cdef turbojpeg.tjhandle tj_context

    def __cinit__(self,char *dev_name):
        pass

    def __init__(self,char *dev_name):
        self.dev_name = dev_name
        self.dev_handle = self.open_device()
        self.verify_device()
        self.get_format()

        self._transport_formats = None
        self._frame_rates = None
        self._frame_sizes = None

        self._buffer_active = False
        self._allocated_buf_n = 0

        self._buffers_initialized = False
        self._camera_streaming = False

        # if timebase == None:
        #     logger.debug("Capture will run with default system timebase")
        #     self.timebase = c_double(0)
        # elif isinstance(timebase,c_double):
        #     logger.debug("Capture will run with app wide adjustable timebase")
        #     self.timebase = timebase
        # else:
        #     logger.error("Invalid timebase variable type. Will use default system timebase")
        #     self.timebase = c_double(0)
        #self._use_hw_timestamps = use_hw_timestamps
        #
        #
        #setup for jpeg converter
        self.tj_context = turbojpeg.tjInitDecompress()

        #set some sane defaults:
        self.transport_format = 'MJPG'


    def close(self):
        self.stop()
        self.deinit_buffers()
        self.close_device()

    def __dealloc__(self):
        turbojpeg.tjDestroy(self.tj_context)

        if self.dev_handle != -1:
            self.close()

    def get_frame(self):
        cdef Frame out_frame
        if not self._camera_streaming:
            self.init_buffers()
            self.start()

        if self._buffer_active:
            if self.xioctl(v4l2.VIDIOC_QBUF,&self._active_buffer) == -1:
                raise Exception("Could not queue buffer")
            else:
                self._buffer_active = False

        self.wait_for_buffer_avaible()


        #deque the buffer
        self._active_buffer.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
        self._active_buffer.memory = v4l2.V4L2_MEMORY_MMAP
        if self.xioctl(v4l2.VIDIOC_DQBUF, &self._active_buffer) == -1:
            if errno == EAGAIN: # no buffer available yet.
                raise Exception("Fixme")

            elif errno == EIO:
                # Can ignore EIO, see spec. 
                pass # fall through 
            else:
                raise Exception("VIDIOC_DQBUF")

        self._buffer_active = True

        # this is taken from the demo but it seams overly causious
        assert(self._active_buffer.index < self._allocated_buf_n)

        #now we hold a valid frame
        # print self._active_buffer.timestamp.tv_sec,',',self._active_buffer.timestamp.tv_usec,self._active_buffer.bytesused,self._active_buffer.index
        out_frame = Frame()
        out_frame.tj_context = self.tj_context
        out_frame.timestamp = <double>self._active_buffer.timestamp.tv_sec + <double>self._active_buffer.timestamp.tv_usec / 10e6
        out_frame.width,out_frame.height = self._frame_size
        
        cdef buffer_handle new_buf = buffer_handle()
        new_buf.start = (<buffer_handle>self.buffers[self._active_buffer.index]).start
        new_buf.length = self._active_buffer.bytesused


        if self._transport_format == v4l2.V4L2_PIX_FMT_MJPEG:
            out_frame.jpeg_buffer  = new_buf
        elif self._transport_format == v4l2.V4L2_PIX_FMT_YUYV:
            out_frame._yuyv_buffer = new_buf
        else:
            raise Exception("Reading Tranport format data '%s' is not implemented."%self.transport_format)
        return out_frame


    cdef wait_for_buffer_avaible(self):
        cdef select.fd_set fds
        cdef time.timeval tv
        cdef int r
        while True:
            select.FD_ZERO(&fds)
            select.FD_SET(self.dev_handle, &fds)
            tv.tv_sec = 3
            tv.tv_usec = 0

            r = select.select(self.dev_handle + 1, &fds, NULL, NULL, &tv)

            if r == 0:
                raise Exception("select timeout")
            elif r == -1:
                if errno != EINTR:
                    raise Exception("Select Error")
                else:
                    #try again
                    pass
            else:
                return


    cdef xioctl(self, int request, void *arg):
        cdef int r
        while True:
            r = ioctl(self.dev_handle, request, arg)
            if -1 != r or EINTR != errno:
                break
        return r

    cdef open_device(self):
        cdef stat.struct_stat st
        cdef int dev_handle = -1
        if -1 == stat.stat(self.dev_name, &st):
            raise Exception("Cannot find '%s'. Error: %d, %s\n"%(self.dev_name, errno, strerror(errno) ))
        if not stat.S_ISCHR(st.st_mode):
            raise Exception("%s is no device\n"%self.dev_name)

        dev_handle = fcntl.open(self.dev_name, fcntl.O_RDWR | fcntl.O_NONBLOCK, 0)
        if -1 == dev_handle:
            raise Exception("Cannot open '%s'. Error: %d, %s\n"%(self.dev_name, errno, strerror(errno) ))
        return dev_handle


    cdef close_device(self):
        if unistd.close(self.dev_handle) == -1:
            raise Exception("Could not close device. Handle: '%s'. Error: %d, %s\n"%(self.dev_handle, errno, strerror(errno) ))
        self.dev_handle = -1


    cdef verify_device(self):
        cdef v4l2.v4l2_capability cap
        if self.xioctl(v4l2.VIDIOC_QUERYCAP, &cap) ==-1:
            if EINVAL == errno:
                raise Exception("%s is no V4L2 device\n"%self.dev_name)
            else:
                raise Exception("Error during VIDIOC_QUERYCAP: %d, %s"%(errno, strerror(errno) ))
        
        if not (cap.capabilities & v4l2.V4L2_CAP_VIDEO_CAPTURE):
            raise Exception("%s is no video capture device"%self.dev_name)

        if not (cap.capabilities & v4l2.V4L2_CAP_STREAMING):
            raise Exception("%s does not support streaming i/o"%self.dev_name)


    cdef stop(self):
        cdef v4l2.v4l2_buf_type buf_type
        if self._camera_streaming:
            buf_type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
            if self.xioctl(v4l2.VIDIOC_STREAMOFF,&buf_type) == -1:
                self.close()
                raise Exception("Could not deinit buffers.")

            self._camera_streaming = False
            logger.debug("Capure stopped.")



    cdef start(self):
        cdef v4l2.v4l2_buffer buf
        cdef v4l2.v4l2_buf_type buf_type
        if not self._camera_streaming:
            for i in range(len(self.buffers)):
                buf.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
                buf.memory = v4l2.V4L2_MEMORY_MMAP
                buf.index = i
                if self.xioctl(v4l2.VIDIOC_QBUF, &buf) == -1:
                    raise Exception('VIDIOC_QBUF')
        
            buf_type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
            if self.xioctl(v4l2.VIDIOC_STREAMON, &buf_type) ==-1:
                raise Exception("VIDIOC_STREAMON")
            self._camera_streaming = True
            logger.debug("Capure started.")

    

    cdef init_buffers(self):
        cdef v4l2.v4l2_requestbuffers req
        cdef v4l2.v4l2_buffer buf
        if not self._buffers_initialized:
            req.count = 4
            req.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
            req.memory = v4l2.V4L2_MEMORY_MMAP

            if self.xioctl(v4l2.VIDIOC_REQBUFS, &req) == -1:
                if EINVAL == errno:
                    raise Exception("%s does not support memory mapping"%self.dev_name)
                else:
                    raise Exception("VIDIOC_REQBUFS failed")

            if req.count < 2:
                raise Exception("Insufficient buffer memory on %s\n"%self.dev_name)

            self.buffers = []
            self._allocated_buf_n = req.count

            for buf_n in range(req.count):
                buf.type        = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
                buf.memory      = v4l2.V4L2_MEMORY_MMAP
                buf.index       = buf_n
                if self.xioctl(v4l2.VIDIOC_QUERYBUF, &buf) == -1:
                    raise Exception("VIDIOC_QUERYBUF")

                b = buffer_handle() 
                b.length = buf.length
                b.start = mman.mmap(NULL,#start anywhere
                                    buf.length,
                                    mman.PROT_READ | mman.PROT_WRITE,#required
                                    mman.MAP_SHARED,#recommended
                                    self.dev_handle, buf.m.offset)
                if <int>b.start == mman.MAP_FAILED:
                    raise Exception("MMAP Error")
                self.buffers.append(b)

            self._buffers_initialized = True
            logger.debug("Buffers initialized")


    cdef deinit_buffers(self):
        cdef buffer_handle b
        if self._buffers_initialized:
            for b in self.buffers:
                if mman.munmap(b.start, b.length) ==-1:
                    raise Exception("munmap error")
            self.buffers = []
            self._buffers_initialized = False
            self._allocated_buf_n = 0

            logger.debug("Buffers deinitialized")


    cdef set_format(self):
        cdef v4l2.v4l2_format  format
        format.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
        format.fmt.pix.width       = self.frame_size[0]
        format.fmt.pix.height      = self.frame_size[1]
        format.fmt.pix.pixelformat = self._transport_format


        format.fmt.pix.field       = v4l2.V4L2_FIELD_ANY
        if self.xioctl(v4l2.VIDIOC_S_FMT, &format) == -1:
            self.close()
            raise Exception("Could not set v4l2 format")


        cdef v4l2.v4l2_streamparm streamparm
        streamparm.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
        streamparm.parm.capture.timeperframe.numerator = self.frame_rate[0]
        streamparm.parm.capture.timeperframe.denominator = self.frame_rate[1]
        if self.xioctl(v4l2.VIDIOC_S_PARM, &streamparm) == -1:
            self._close()
            raise Exception("Could not set v4l2 parameters")
       

    cdef get_format(self):
        cdef v4l2.v4l2_format format
        format.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
        if self.xioctl(v4l2.VIDIOC_G_FMT, &format) == -1:
            self.close()
            raise Exception("Could not get v4l2 format")
        else:
            self._frame_size = format.fmt.pix.width,format.fmt.pix.height
            self._transport_format = format.fmt.pix.pixelformat

        cdef v4l2.v4l2_streamparm streamparm
        streamparm.type = v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
        if self.xioctl(v4l2.VIDIOC_G_PARM, &streamparm) == -1:
            self._close()
            raise Exception("Could not get v4l2 parameters")
        else:
            self._frame_rate = streamparm.parm.capture.timeperframe.numerator,streamparm.parm.capture.timeperframe.denominator




    property transport_formats:
        def __get__(self):
            cdef v4l2.v4l2_fmtdesc fmt
            if self._transport_formats is None:
                fmt.type =  v4l2.V4L2_BUF_TYPE_VIDEO_CAPTURE
                fmt.index = 0
                formats = []
                while self.xioctl(v4l2.VIDIOC_ENUM_FMT,&fmt)>=0:
                    formats.append( fourcc_string(fmt.pixelformat ) )
                    fmt.index += 1
                logger.debug("Reading Transport formats: %s"%formats)
                self._transport_formats = formats
            return self._transport_formats

        def __set__(self,val):
            raise Exception("Read Only")


    property frame_sizes:
        def __get__(self):
            cdef  v4l2.v4l2_frmsizeenum frmsize
            if self._frame_sizes is None:
                frmsize.pixel_format = fourcc_u32(self.transport_format)
                frmsize.index = 0
                sizes = []
                while self.xioctl(v4l2.VIDIOC_ENUM_FRAMESIZES, &frmsize) >= 0:
                    if frmsize.type == v4l2.V4L2_FRMSIZE_TYPE_DISCRETE:
                        sizes.append((frmsize.discrete.width,frmsize.discrete.height))
                    elif frmsize.type == v4l2.V4L2_FRMSIZE_TYPE_STEPWISE:
                        sizes.append( (frmsize.stepwise.max_width, frmsize.stepwise.max_height) )
                    frmsize.index+=1
                logger.debug("Reading frame sizes@'%s': %s"%(self.transport_format,sizes) )
                self._frame_sizes = sizes 

            return self._frame_sizes

        def __set__(self,val):
            raise Exception("Read Only")


    property frame_rates:
        def __get__(self):
            cdef v4l2.v4l2_frmivalenum interval

            if self._frame_rates is None:
                interval.pixel_format = fourcc_u32(self.transport_format)
                interval.width,interval.height = self.frame_size
                interval.index = 0
                self.xioctl(v4l2.VIDIOC_ENUM_FRAMEINTERVALS,&interval)
                rates = []
                if interval.type == v4l2.V4L2_FRMIVAL_TYPE_DISCRETE:
                    while self.xioctl(v4l2.VIDIOC_ENUM_FRAMEINTERVALS,&interval) >= 0:
                        rates.append((interval.discrete.numerator,interval.discrete.denominator))
                        interval.index += 1
                #non-discreete rates are very seldom, the second and third case should never happen
                elif interval.type == v4l2.V4L2_FRMIVAL_TYPE_STEPWISE or interval.type == v4l2.V4L2_FRMIVAL_TYPE_CONTINUOUS:
                    minval = float(interval.stepwise.min.numerator)/interval.stepwise.min.denominator
                    maxval = float(interval.stepwise.max.numerator)/interval.stepwise.max.denominator
                    if interval.type == v4l2.V4L2_FRMIVAL_TYPE_CONTINUOUS:
                        stepval = 1
                    else:
                        stepval = float(interval.stepwise.step.numerator)/interval.stepwise.step.denominator
                    rates = range(minval,maxval,stepval)
                logger.debug("Reading frame rates@'%s'@%s: %s"%(self.transport_format,self.frame_size,rates) )
                self._frame_rates = rates

            return self._frame_rates

        def __set__(self,val):
            raise Exception("Read Only")


    property transport_format:
        def __get__(self):
            return fourcc_string(self._transport_format)

        def __set__(self,val):
            self._transport_format = fourcc_u32(val)
            self.stop()
            self.deinit_buffers()
            self.set_format()
            self.get_format()
            self._frame_sizes = None
            self._frame_rates = None


    property frame_size:
        def __get__(self):
            return self._frame_size
        def __set__(self,val):
            self._frame_size = val
            self._frame_rates = None
            self.stop()
            self.deinit_buffers()
            self.set_format()
            self.get_format()

    property frame_rate:
        def __get__(self):
            return self._frame_rate
        def __set__(self,val):
            self._frame_rate = val
            self.stop()
            self.deinit_buffers()
            self.set_format()
            self.get_format()
