cdef extern from  "linux/videodev2.h":
    ctypedef unsigned char           __u8
    ctypedef signed char             __s8
    ctypedef unsigned short          __u16
    ctypedef signed short            __s16
    ctypedef unsigned int            __u32
    ctypedef signed int              __s32
    ctypedef unsigned long long int  __u64
    ctypedef signed long long int    __s64

cdef union aaa_t:
    __u32 mem_offset
    long unsigned int userptr

cdef struct bbb:
    __u32 bytesused
    __u32 length
    aaa_t m
    __u32 data_offset
    __u32 reserved[11]
