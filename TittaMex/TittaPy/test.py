from TittaPy import EyeTracker

#print(EyeTracker)
#help(EyeTracker)
#exit()

# Import modules
import pickle
import numpy as np
import time
from psychopy import core
import matplotlib.pyplot as plt

plt.close('all')

# test static functions, then connect to first eye tracker found
EyeTracker.start_logging()
print(EyeTracker.get_SDK_version())
print(EyeTracker.get_system_timestamp())
ets = EyeTracker.find_all_eye_trackers()
print(ets)
if len(ets)==0:
    EThndl = EyeTracker('tet-tcp://169.254.10.20')
else:
    EThndl = EyeTracker(ets[0].address)
print(EThndl)

# test properties
# 1. these are read-write
EThndl.frequency = 150
print(EThndl.frequency)
print(EThndl)
EThndl.frequency = 600
print(EThndl.tracking_mode)
print(EThndl.device_name)
# 2. these are read only
print(EThndl.serial_number)
print(EThndl.model)
print(EThndl.firmware_version)
print(EThndl.runtime_version)
print(EThndl.address)
print(EThndl.capabilities)
print(EThndl.supported_frequencies)
print(EThndl.supported_modes)
print(EThndl.track_box)
print(EThndl.display_area)

# with a 4C, test:
#EThndl.clear_licenses()
#EThndl.apply_licenses()

# test calibration (just go through the motions without display, seems to succeed anyway with two positions if there are eyes)
EThndl.leave_calibration_mode(True)

print("enter_calibration_mode:")
EThndl.enter_calibration_mode(False)
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.status_string)
pickle.dump(res,open( "save.pkl", "wb" ))
res2 = pickle.load( open( "save.pkl", "rb" ) )

print("calibration_discard_data:")
EThndl.calibration_discard_data([0.1,0.1])
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.work_item.coordinates)
print(res.status_string)
pickle.dump(res,open( "save.pkl", "wb" ))
res2 = pickle.load( open( "save.pkl", "rb" ) )

print("calibration_collect_data:")
time.sleep(0.5)
EThndl.calibration_collect_data([0.5,0.5])
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
time.sleep(0.5)
EThndl.calibration_collect_data([0.5,0.5])
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
EThndl.calibration_collect_data([0.45,0.45])
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.work_item.coordinates)
print(res.status_string)
pickle.dump(res,open( "save.pkl", "wb" ))
res2 = pickle.load( open( "save.pkl", "rb" ) )

print(EThndl.calibration_get_status())

print("calibration_compute_and_apply:")
EThndl.calibration_compute_and_apply()
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.status_string)
print(res.calibration_result)
pickle.dump(res,open( "save.pkl", "wb" ))
res2 = pickle.load( open( "save.pkl", "rb" ) )

print("calibration_get_data:")
EThndl.calibration_get_data()
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.status_string)
#print(res.calibration_data)
pickle.dump(res,open( "save.pkl", "wb" ))
res2 = pickle.load( open( "save.pkl", "rb" ) )

print("calibration_apply_data:")
EThndl.calibration_apply_data(res.calibration_data)
res = None
while res==None:
    res = EThndl.calibration_retrieve_result()
print(res.work_item.action)
print(res.status_string)
   
#%% Record some data (and test all streams while we do so)
print(EThndl.has_stream('gaze'))
print(EThndl.is_recording('gaze'))
success = EThndl.start('gaze')
success = EThndl.start('positioning')
success = EThndl.start('eye_image')
success = EThndl.start('external_signal')
success = EThndl.start('time_sync')
success = EThndl.start('notification')
print(EThndl.is_recording('gaze'))
core.wait(0.2)


'''
Since samples are pulled in callbacks with the Tobii SDK, it may get
hiccups if your script is doing something very computationally heavy,
without allowing significant sleeps (which would allow the callback to
be called and therefore all samples to be collected appropriately).

This can be tested in a while-loop like the one below.

TobiiWrapper doesn't show this problem luckily, so the below loop should be fine
'''
dur = 4 # Record what should be this many seconds of data
n_samples = EThndl.frequency * dur

out = []
k = 0
ts = 0
ts_old = 0

t0 = time.perf_counter()
while k < n_samples:
    samples = EThndl.peek_N('gaze')
    if len(samples)>0:
        ts = samples[0].system_time_stamp

    if ts == ts_old:
        #core.wait(0.00001) # Wait 1/10 ms
        continue
   
    out.append([time.perf_counter(), ts])
    k += 1
    ts_old = ts

    if out[-1][0]-t0>dur/2:
        # start recording eye openness. Also, if set to true, any
        # calls to start or stop either gaze or eye_openness will
        # start or stop both
        EThndl.set_include_eye_openness_in_gaze(True)
   
print(time.perf_counter() - t0)
success = EThndl.stop('positioning')
success = EThndl.stop('gaze')   # NB: also stops eye_openness
success = EThndl.stop('eye_image')
success = EThndl.stop('external_signal')
success = EThndl.stop('time_sync')
success = EThndl.stop('notification')


#%% Plot data captured in real time (tobii time stamps, and loop intervals)
out = np.array(out)
plt.figure()
plt.plot(np.diff(out[:, 0] * 1000))
plt.figure()
plt.plot(np.diff(out[:, 1] / 1000))

#%% Plot timestamps of samples in the buffer (and test pickle save and load)
all_samples = EThndl.peek_N('gaze',10000000)
pickle.dump(all_samples,open( "save.pkl", "wb" ))
print(all_samples[-1])
ut = []
for i in all_samples:
    ut.append(i.system_time_stamp)
   
plt.figure()
plt.plot(np.diff(ut) / 1000)


all_samples2 = pickle.load( open( "save.pkl", "rb" ) )
ut2 = []
for i in all_samples2:
    ut2.append(i.system_time_stamp)
   
plt.figure()
plt.plot(np.diff(ut2) / 1000)

all_samples3 = EThndl.consume_N('gaze',10000000)
all_samples4 = EThndl.consume_time_range('gaze')
print([len(all_samples), len(all_samples2), len(all_samples3), len(all_samples4)])
    

all_images = EThndl.peek_time_range('eye_image') # by default peeks all
print(all_images[0])
pickle.dump(all_images,open( "save.pkl", "wb" ))

plt.figure()
plt.imshow(all_images[0].image, cmap="gray")

all_images2 = pickle.load( open( "save.pkl", "rb" ) )
plt.figure()
plt.imshow(all_images2[0].image, cmap="gray")


def save_and_load_test(which: str, data=None):
    data = EThndl.peek_N(which)
    if not data:
        import warnings
        warnings.warn(f"no data for {which} stream",RuntimeWarning)
        return
    print(data[0])
    pickle.dump(data,open( "save.pkl", "wb" ))
    data2 = pickle.load( open( "save.pkl", "rb" ) )
    print(data2[0])

save_and_load_test('external_signal')
save_and_load_test('time_sync')
save_and_load_test('positioning')
save_and_load_test('notification')


l=EThndl.get_log(True)  # True means the log is consumed. False (default) its only peeked.
print(l)
pickle.dump(l,open( "save.pkl", "wb" ))
l2 = pickle.load( open( "save.pkl", "rb" ) )
print(l2)
EThndl.stop_logging()


plt.show()

