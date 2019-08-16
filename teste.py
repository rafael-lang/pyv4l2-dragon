import v4l2
import cv2
import numpy as np

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

# cap.frame_size = (1280, 720)
# cap.frame_rate = (1,30)
# controls = cap.enum_controls()
# print(controls)
# cap.set_control(controls[0]['id'],controls[0]['default'])
# print(cap.get_control(controls[0]['id']))
# print('Will capture at:',cap.transport_format,cap.frame_size,cap.frame_rate)
# for x in range(2000):
# 	try:
# 		frame = cap.get_frame_robust()
# 	except IOError: 
# 		print("could not grab frame")
# 		break
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
# 	cv2.imshow("img",y)
# 	#cv2.imshow("u",u)
# 	#cv2.imshow("v",v)

# 	cv2.waitKey(1)
# 	# print img

cap.close()
cap = None
