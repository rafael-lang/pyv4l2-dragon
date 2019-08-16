import v4l2
import cv2
import numpy as np

file = '/dev/video0'
print(v4l2.list_devices())
cap = v4l2.CaptureDragon(file.encode('utf-8'))
print(cap)

print(cap.get_info())
cap.transport_formats
print(cap.frame_rate)
print(cap.frame_size)
print(cap.transport_format,cap.transport_formats)

cap.frame_size = (1280, 720)
cap.frame_rate = (1,30)
controls = cap.enum_controls()
print(controls)
cap.set_control(controls[0]['id'],controls[0]['default'])
print(cap.get_control(controls[0]['id']))
print('Will capture at:',cap.transport_format,cap.frame_size,cap.frame_rate)
for x in range(2000):
	try:
		frame = cap.get_frame_robust()
	except IOError: 
		print("could not grab frame")
		break
	# print frame.width,frame.height
	# print frame.d
	y= frame.bgr
	# print v.shape
	#img = frame.yuv
	#y,u,v = img
	# y = frame.bgr
	# print y.data
	# y = np.ones((1080,1920b,1))
	# print y[].shape
	# print u[]s.shape
	cv2.imshow("img",y)
	#cv2.imshow("u",u)
	#cv2.imshow("v",v)

	cv2.waitKey(1)
	# print img
cap.close()
cap = None

