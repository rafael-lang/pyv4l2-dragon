import ctypes as C
from ctypes.util import find_library
import numpy as np
import cv2

H = 480
W = 640
SIZE = H*W
SIZE2 = int(SIZE/2)

libc = C.CDLL(find_library('c'))
libc.malloc.restype = C.c_void_p

# get a pointer to a block of data from malloc
data_pointer_y = libc.malloc(SIZE * C.sizeof(C.c_uint8))
data_pointer_y = C.cast(data_pointer_y,C.POINTER(C.c_uint8))

data_pointer_uv = libc.malloc(SIZE2 * C.sizeof(C.c_uint8))
data_pointer_uv = C.cast(data_pointer_uv,C.POINTER(C.c_uint8))

for i in range(SIZE):
    data_pointer_y[i] = min(i,255)
    
for i in range(SIZE2):
    data_pointer_uv[i] = min(i, 255)

array_y  = np.ctypeslib.as_array(data_pointer_y, shape=(SIZE,))
array_uv = np.ctypeslib.as_array(data_pointer_uv, shape=(SIZE2,))

print('Y:')
print(array_y.shape)
print(data_pointer_y)
print(array_y)

print('UV:')
print(array_uv.shape)
print(data_pointer_uv)
print(array_uv)

yLength = SIZE
uvLength = int(SIZE/4)
y = np.ctypeslib.as_array(data_pointer_y, shape=(yLength,)).reshape((H, W))
u = np.ctypeslib.as_array(data_pointer_uv[0:2*uvLength:2], shape=(uvLength,)).reshape((int(H/2), int(W/2)))
v = np.ctypeslib.as_array(data_pointer_uv[1:2*uvLength:2], shape=(uvLength,)).reshape((int(H/2), int(W/2)))

print('y')
print(y.shape)
print(y)
print('u')
print(u.shape)
print(u)
print('v')
print(v.shape)
print(v)


cv2.imshow("y", y)
cv2.imshow("u", u)
cv2.imshow("v", v)
cv2.waitKey(0)

del array_y
del array_uv
del y
del u
del v
libc.free(data_pointer_y)
libc.free(data_pointer_uv)
