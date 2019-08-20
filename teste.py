import v4l2
import cv2
import numpy as np
import time

# Dragon + D3 Mezzanine
file = '/dev/video3'
subfile = '/dev/v4l-subdev10'
cap = v4l2.CaptureDragon(file.encode('utf-8'), subfile.encode('utf-8'))

# Webcam
#file = '/dev/video0'
#cap = v4l2.Capture(file.encode('utf-8'))

# All
print('Capture devices:')
print(v4l2.list_devices())

print('Capture: %s'%cap.get_info())

print('Transport formats:')
print(cap.transport_formats)

print('Transport format: %s'%cap.transport_format)

print('Frame sizes @ %s:'%cap.transport_format)
print(cap.frame_sizes)

print('Frame size: %s x %s'%(cap.frame_size[0], cap.frame_size[1]))

# Webcam
#print('Frame rates @ %s - %s x %s:'%(cap.transport_format, cap.frame_size[0], cap.frame_size[1]))
#print(cap.frame_rates)

#print('Frame rate: %s/%s'%(cap.frame_rate[0], cap.frame_rate[1]))

#print('Controls:')
#print(cap.enum_controls())

#cap.frame_size = (2592, 1936)
#cap.frame_rate = (1,30)
#controls = cap.enum_controls()
#print(controls)
#cap.set_control(controls[0]['id'],controls[0]['default'])
#print(cap.get_control(controls[0]['id']))
print('Will capture at:',cap.transport_format,cap.frame_size)

ant = time.time()
r = 3000
start = time.time()
for x in range(r):
    try:
        a = time.time()
        frame = cap.get_frame()
        b = time.time()
    except IOError:
        print("could not grab frame")
        break

# 	# print frame.width,frame.height
# 	# print frame.d
# 	y= frame.bgr
# 	# print v.shape
# 	#img = frame.yuv
# 	#y,u,v = img
# 	# y = frame.bgr
# 	# print y.data
# 	# y = np.ones((1080,1920b,1))
# 	# print y[].shape
# 	# print u[]s.shape

#    y,u,v = frame.yuvlang
#    cv2.imshow("y",y)
#    cv2.imshow("u",u)
#    cv2.imshow("v",v)
#    cv2.waitKey(1)

#    yuv,bgr = frame.bgr
#    c = time.time()
#    cv2.imshow("img",yuv)
#    cv2.imshow("img",bgr)
#    d = time.time()
#    cv2.waitKey(1)

#    y,u,v = frame.yuv
#    c = time.time()
#    cv2.imshow("img",y)
#    d = time.time()
#    cv2.waitKey(1)

    y = frame.gray
    c = time.time()
    cv2.imshow("img",y)
    d = time.time()
    cv2.waitKey(1)

    print('   ')
    print('cap: %.2f'%(1000*(b-a)))
    print('cvt: %.2f'%(1000*(c-b)))
    print('dis: %.2f'%(1000*(d-c)))
    print('fps -d: %.2f'%(1/(c-a)))
    print('fps: %.2f'%(1/(time.time()-ant)))
    ant = time.time()

# 	# print img

print('fps_avg: %.2f'%(r/(time.time()-start)))

cap.close()
cap = None
