#!/usr/bin/env python
import pygame
from pygame.locals import *
import serial
import sys

print sys.argv
if len(sys.argv) < 2:
	print "Please select a serial port to use! e.g. /dev/ttyUSB0 or COM4"
	sys.exit(1)

class SegmentImage:
	def __init__(self,filename):
		self.images = []
		image = pygame.image.load(filename)
		self.images.append(image)
		image = image.copy()
		arr = pygame.surfarray.pixels3d(image)
		arr[:,:,0] = arr[:,:,0]/4
		del arr
		self.images.append(image)
		
	def __call__(self,selected):
		return self.images[1-selected]

class RotatableSegmentImage:
	def __init__(self,filename):
		images = []
		image = pygame.image.load(filename)
		images.append(image)
		image = image.copy()
		arr = pygame.surfarray.pixels3d(image)
		arr[:,:,0] = arr[:,:,0]/4
		del arr
		images.append(image)
		self.images = [(image,pygame.transform.rotate(image,90)) for image in images]
		
	def __call__(self,selected,rotated):
		return self.images[1-selected][rotated]
		
class SegmentNumber:
	def __init__(self,number):
		self.number = number
		
	def render(self,screen,center):
		
		for i in range(7):
			enabled = (1<<i)&self.number is not 0
			segment = segment_positions[i]
			offsets = [0,0]
			rotation = segment[2]
			image = images["segment"](enabled,segment[2])
			offsets[1-rotation] = -image.get_size()[1-rotation]/2
			x = center[0] + segment[0] + offsets[0]
			y = center[1] + segment[1] + offsets[1]
			screen.blit(image,(x,y))
			
class SerialWrapper:
	def __init__(self,port):
		self.serial = serial.Serial(port,19200)
		
	def read(self):
		byte = ord(self.serial.read())
		print ">0x%02x" % byte
		return byte
		
	def write(self,byte):
		self.serial.write(str(byte))
		print "<0x%02x" % byte
		

pygame.init()

pygame.mixer.music.load('alarm.wav')

class Buzzer:
	def __init__(self):
		self.sound_playing = False

	def sound_sound(self):
		if not self.sound_playing:
			pygame.mixer.music.play(-1)
			self.sound_playing = True
			
	def stop_sound(self):
		if self.sound_playing:
			pygame.mixer.music.stop()
			self.sound_playing = False

buzzer = Buzzer()
set_sound = [buzzer.sound_sound,buzzer.stop_sound]

width = 1024
height = 768

screen = pygame.display.set_mode((width,height))
pygame.display.set_caption("display")
images = {
	"segment": RotatableSegmentImage("segment.png"),
	"colon": SegmentImage("colon.png"),
	"alarm": SegmentImage("alarm.png"),
}
scale = 64
image_scale = scale/4
segment_positions = [(-scale/2,-scale,0),(-scale/2,-scale,1),(scale/2,-scale,1),(-scale/2,0,0),(-scale/2,0,1),(scale/2,0,1),(-scale/2,scale,0)]			
			
segments = []
colons = [False,False]
alarm = False
data = [0,]*7
ser = SerialWrapper(sys.argv[1])

for i in range(6):
	segments.append(SegmentNumber(0))
		
total_bytes = 0
			
while True:
	for event in pygame.event.get():
		if event.type is QUIT:
			sys.exit()
	pygame.draw.rect(screen,(0,0,0),(0,0,width,height))
	segment_pairs = []
	for i in xrange(len(segments)/2):
		segment_pairs.append(segments[i*2:i*2+2])
	for i, segment_pair in enumerate(segment_pairs):
		x = width/2 + (i-(len(segment_pairs)-1)/2.0)*scale*3
		y = height/2
		for j,segment in enumerate(segment_pair):
			segment.render(screen,(x+(scale/2+8)*(-1,1)[j],y))
	for i in xrange(len(segment_pairs)-1):
		x = width/2 + (i-(len(segment_pairs)-2)/2.0)*scale*3
		y = height/2
		image = images["colon"](colons[i])
		screen.blit(image,(x-image.get_width()/2,y-image.get_height()/2))
	alarm_img = images["alarm"](alarm)
	screen.blit(alarm_img,(width/2+len(segment_pairs)*scale*1.5,height/2-scale))#(width/2+scale*3*len(segment_pairs),height/2-scale))
	pygame.display.set_icon(alarm_img)		#disable this if it bothers you
	serial_data = []
	while True:
		total_bytes = total_bytes + 1
		byte = ser.read()
		if byte == 0x80:
			serial_data = []
			print "RESET!"
			ser.write(0x3)
			continue
		elif byte == 0x81:
			serial_data = [0,]*7
			print "CLEAR!"
			ser.write(0x3)
			break
		serial_data.append(byte)
		ser.write(0x2)
		if len(serial_data) is 7:
			print "UPDATE: " + str(serial_data)
			ser.write(0x1)
			break
	print "total bytes received: " + str(total_bytes)
	for i,byte in enumerate(serial_data[0:6]):
		segments[i].number = byte
	last_byte = serial_data[-1]
	set_sound[bool(1<<3)]()
	colons = [bool(1<<1&last_byte),bool(1<<2&last_byte)]
	alarm = bool(1<<0&last_byte)
	icon = pygame.transform.scale(screen,(32,32))
	pygame.display.update()
		
