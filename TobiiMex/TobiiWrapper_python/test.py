﻿import TobiiWrapper

#print(TobiiWrapper)
#help(TobiiWrapper)
#help(TobiiWrapper.TobiiWrapper)




'''
Since samples are pulled in callbacks with the Tobii SDK, it may get
hick-ups if your script is doing something very computationally heavy,
without allowing significant sleeps (which would allow the callback to
be called and therefore all sample to be collected appropriately).

This can be tested in a while-loop like the one below.                                    
'''
# Import modules
import pickle
import numpy as np
import time
from psychopy import core
import matplotlib.pyplot as plt

plt.close('all')

#%% ET settings
tw = TobiiWrapper.TobiiWrapper('tet-tcp://169.254.10.20')
print(tw)
   
#%% Record some data
success = tw.start('gaze')
success = tw.start('eyeImage')
core.wait(0.2)
n_samples = 600 * 2 # Record two seconds of data at 600 Hz

out = []
k = 0
ts = 0
ts_old = 0

t0 = time.clock()
while k < n_samples:
    samples = tw.peekN('gaze')
    if len(samples)>0:
        ts = samples[0].system_time_stamp

    if ts == ts_old:
        #core.wait(0.00001) # Wait 1/10 ms
        continue
   
    out.append([time.clock(), ts])
    k += 1
    ts_old = ts
   
print(time.clock() - t0)
success = tw.stop('gaze')
success = tw.stop('eyeImage')


#%% Plot data captured in real time (tobii time stamps, and loop intervals)
out = np.array(out)
plt.plot(np.diff(out[:, 0] * 1000))
plt.figure()
plt.plot(np.diff(out[:, 1] / 1000))

#%% Plot timestamps of samples in the buffer (and test pickle save and load)
all_samples = tw.peekN('gaze',10000000)
pickle.dump(all_samples,open( "save.pkl", "wb" ))
#print(all_samples[0])
#print(all_samples[0].left)
#print(all_samples[0].left.gaze_point.on_display_area.x)
#print(all_samples[0].left.gaze_point.on_display_area)
#print(all_samples[0].left.gaze_point)
#print(all_samples[0].left)
print(all_samples[0])
ut =[]
for i in all_samples:
    ut.append(i.system_time_stamp)
   
plt.figure()
plt.plot(np.diff(ut) / 1000)


all_samples2 = pickle.load( open( "save.pkl", "rb" ) )
ut2 =[]
for i in all_samples2:
    ut2.append(i.system_time_stamp)
   
plt.figure()
plt.plot(np.diff(ut2) / 1000)


all_images = tw.peekN('eyeImage',10000000)
print(all_images[0])
pickle.dump(all_images,open( "save2.pkl", "wb" ))

plt.figure()
plt.imshow(all_images[0].image)

all_images2 = pickle.load( open( "save2.pkl", "rb" ) )
plt.figure()
plt.imshow(all_images2[0].image)

plt.show()

