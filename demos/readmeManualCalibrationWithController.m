% this demo code is part of Titta, a toolbox providing convenient access to
% eye tracking functionality using Tobii eye trackers
%
% Titta can be found at https://github.com/dcnieho/Titta. Check there for
% the latest version.
% When using Titta, please cite the following paper:
%
% Niehorster, D.C., Andersson, R. & Nystrom, M., (2020). Titta: A toolbox
% for creating Psychtoolbox and Psychopy experiments with Tobii eye
% trackers. Behavior Research Methods.
% doi: https://doi.org/10.3758/s13428-020-01358-8

% This version of readme.m demonstrates operation with separate
% presentation and operator screens. It furthermore demonstrates Titta's
% manual calibration mode that is designed for working with non-compliant
% participants. This version uses a controller for automatic positioning
% and calibration training, and uses video stimuli as calibration targets.
% 
% NB: some care is taken to not update operator screen during timing
% critical bits of main script
% NB: this code assumes main and secondary screen have the same resolution.
% Titta's setup displays work fine if this is not the case, but the
% real-time gaze display during the mock experiment is not built for that.
% So if your two monitors have different resolutions, either adjust the
% code, or look into solutions e.g. with PsychImaging()'s 'UsePanelFitter'.

clear all
sca

DEBUGlevel              = 0;
fixClrs                 = [0 255];
bgClr                   = 127;
eyeColors               = {[255 127 0],[0 95 191]}; % for live data view on operator screen
videoFolder             = fullfile(PsychtoolboxRoot,'PsychDemos/MovieDemos/');
videoExt                = 'mov';
numCalPoints            = 2;    % 2, 3 or 5
% task parameters
fixTime                 = .5;
imageTime               = 4;
scrPresenter            = 1;
scrOperator             = 2;
% live view parameters
dataWindowDur           = 500;  % ms

% You can run addTittaToPath once to "install" it, or you can simply add a
% call to it in your script so each time you want to use Titta, it is
% ensured it is on path
home = cd;
cd ..;
addTittaToPath;
cd(home);

try
    eyeColors = cellfun(@color2RGBA,eyeColors,'uni',false);
    
    % get setup struct (can edit that of course):
    settings = Titta.getDefaults('Tobii Pro Spectrum');
    % request some debug output to command window, can skip for normal use
    settings.debugMode      = true;
    % customize colors of setup and calibration interface (yes, colors of
    % everything can be set, so there is a lot here).
    % 1. setup screen
    settings.UI.setup.bgColor       = bgClr;
    settings.UI.setup.instruct.color= fixClrs(1);
    settings.UI.setup.fixBackColor  = fixClrs(1);
    settings.UI.setup.fixFrontColor = fixClrs(2);
    % override the instruction shown on the setup screen, don't need that
    % much detail when you have a separate operator screen
    settings.UI.setup.instruct.strFun   = @(x,y,z,rx,ry,rz) 'Position yourself such that the two circles overlap.';
    % 2. validation result screen
    settings.UI.val.bgColor                 = bgClr;
    settings.UI.val.avg.text.color          = fixClrs(1);
    settings.UI.val.fixBackColor            = fixClrs(1);
    settings.UI.val.fixFrontColor           = fixClrs(2);
    settings.UI.val.onlineGaze.fixBackColor = fixClrs(1);
    settings.UI.val.onlineGaze.fixFrontColor= fixClrs(2);
    % setup operator display
    settings.UI.mancal.showHead             = true;     % show head display when interface opens
    settings.UI.mancal.headScale            = .35;
    settings.UI.mancal.headPos              = [.5 .175];
    % calibration display
    settings.mancal.cal.pointPos = [settings.mancal.cal.pointPos; .65, .35; .35, .65];
    % calibration display: custom calibration drawer
    calViz                      = VideoCalibrationDisplay();
    settings.mancal.drawFunction= @calViz.doDraw;
    calViz.bgColor              = bgClr;
    % calibration logic: custom controller
    calController = MonkeyCalController([],calViz);
    settings.mancal.cal.pointNotifyFunction = @calController.receiveUpdate;
    settings.mancal.val.pointNotifyFunction = @calController.receiveUpdate;
    settings.mancal.cal.useExtendedNotify = true;
    settings.mancal.val.useExtendedNotify = true;
    settings.UI.button.mancal.toggAuto.visible = true;
    if numCalPoints==2
        calPoints = [6 7];
    elseif numCalPoints==3
        calPoints = [3 6 7];
    elseif numCalPoints==5
        calPoints = [3 1 2 3 4];
    end
    calController.setCalPoints(calPoints,settings.mancal.cal.pointPos(calPoints,:));
    if ismember(numCalPoints,[3 5])
        calController.calAfterFirstCollected = true;
    end
    if DEBUGlevel>0
        calController.logTypes = 1+2*(DEBUGlevel==2);
        calController.logReceiver = 1;
    end
    % calibration logic: only manual calibration attempts since controller
    % controls this
    settings.UI.button.mancal.calibrate.visible = true;
    settings.mancal.cal.autoCalibrate = false;

    
    % init
    EThndl          = Titta(settings);
    % EThndl          = EThndl.setDummyMode();    % just for internal testing, enabling dummy mode for this readme makes little sense as a demo
    EThndl.init();
    calController.EThndl = EThndl;
    nLiveDataPoint  = ceil(dataWindowDur/1000*EThndl.frequency);
    
    if DEBUGlevel>1
        % make screen partially transparent on OSX and windows vista or
        % higher, so we can debug.
        PsychDebugWindowConfiguration;
    end
    if DEBUGlevel
        % Be pretty verbose about information and hints to optimize your code and system.
        Screen('Preference', 'Verbosity', 4);
    else
        % Only output critical errors and warnings.
        Screen('Preference', 'Verbosity', 2);
    end
    Screen('Preference', 'SyncTestSettings', 0.002);    % the systems are a little noisy, give the test a little more leeway
    [wpntP,winRectP] = PsychImaging('OpenWindow', scrPresenter, bgClr, [], [], [], [], 4);
    [wpntO,winRectO] = PsychImaging('OpenWindow', scrOperator , bgClr, [], [], [], [], 4);
    hz=Screen('NominalFrameRate', wpntP);
    Priority(1);
    Screen('BlendFunction', wpntP, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    Screen('BlendFunction', wpntO, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    Screen('Preference', 'TextAlphaBlending', 1);
    Screen('Preference', 'TextAntiAliasing', 2);
    % This preference setting selects the high quality text renderer on
    % each operating system: It is not really needed, as the high quality
    % renderer is the default on all operating systems, so this is more of
    % a "better safe than sorry" setting.
    Screen('Preference', 'TextRenderer', 1);
    KbName('UnifyKeyNames');    % for correct operation of the setup/calibration interface, calling this is required

    calController.scrRes = winRectP(3:4);

    vids = FileFromFolder(videoFolder, [], videoExt);
    vids = arrayfun(@(x) fullfile(x.folder,x.name), vids, 'uni', false);
    vp = VideoPlayer(wpntP,vids);
    vp.start();
    calViz.setVideoPlayer(vp);

    
    % do calibration
    try
        ListenChar(-1);
    catch ME
        % old PTBs don't have mode -1, use 2 instead which also supresses
        % keypresses from leaking through to matlab
        ListenChar(2);
    end
    tobii.calVal{1} = EThndl.calibrateManual([wpntP wpntO],[],calController);
    ListenChar(0);
    
    
    % later:
    EThndl.buffer.start('gaze');
    WaitSecs(.8);   % wait for eye tracker to start and gaze to be picked up
     
    % send message into ET data file
    EThndl.sendMessage('test');
    
    % First draw a fixation point
    Screen('gluDisk',wpntP,fixClrs(1),winRectP(3)/2,winRectP(4)/2,round(winRectP(3)/100));
    startT = Screen('Flip',wpntP);
    % log when fixation dot appeared in eye-tracker time. NB:
    % system_timestamp of the Tobii data uses the same clock as
    % PsychToolbox, so startT as returned by Screen('Flip') can be used
    % directly to segment eye tracking data
    EThndl.sendMessage('FIX ON',startT);
    
    % read in konijntjes image (may want to preload this before the trial
    % to ensure good timing)
    stimFName   = 'konijntjes1024x768.jpg';
    stimDir     = fullfile(PsychtoolboxRoot,'PsychDemos');
    stimFullName= fullfile(stimDir,stimFName);
    im          = imread(stimFullName);
    tex         = Screen('MakeTexture',wpntP,im);
    nextFlipT   = startT+fixTime-1/hz/2;
    
    % now update also operator screen, once timing critical bit is done
    % if we still have enough time till next flipT, update operator display
    while nextFlipT-GetSecs()>2/hz   % arbitrarily decide two frames is enough headway
        Screen('gluDisk',wpntO,fixClrs(1),winRectO(3)/2,winRectO(4)/2,round(winRectO(3)/100));
        drawLiveData(wpntO,EThndl.buffer.peekN('gaze',nLiveDataPoint),dataWindowDur,eyeColors{:},4,winRectO(3:4));
        Screen('Flip',wpntO);
    end
        
    
    % show on screen and log when it was shown in eye-tracker time.
    % NB: by setting a deadline for the flip, we ensure that the previous
    % screen (fixation point) stays visible for the indicated amount of
    % time. See PsychToolbox demos for further elaboration on this way of
    % timing your script.
    Screen('DrawTexture',wpntP,tex);                    % draw centered on the screen
    imgT = Screen('Flip',wpntP,nextFlipT);   % bit of slack to make sure requested presentation time can be achieved
    EThndl.sendMessage(sprintf('STIM ON: %s',stimFName),imgT);
    nextFlipT = imgT+imageTime-1/hz/2;
    
    % now update also operator screen, once timing critical bit is done
    % if we still have enough time till next flipT, update operator display
    while nextFlipT-GetSecs()>2/hz   % arbitrarily decide two frames is enough headway
        Screen('DrawTexture',wpntO,tex);
        drawLiveData(wpntO,EThndl.buffer.peekN('gaze',nLiveDataPoint),dataWindowDur,eyeColors{:},4,winRectO(3:4));
        Screen('Flip',wpntO);
    end
    
    % record x seconds of data, then clear screen. Indicate stimulus
    % removed, clean up
    endT = Screen('Flip',wpntP,nextFlipT);
    EThndl.sendMessage(sprintf('STIM OFF: %s',stimFName),endT);
    Screen('Close',tex);
    nextFlipT = endT+1; % lees precise, about 1s give or take a frame, is fine
    
    % now update also operator screen, once timing critical bit is done
    % if we still have enough time till next flipT, update operator display
    while nextFlipT-GetSecs()>2/hz   % arbitrarily decide two frames is enough headway
        drawLiveData(wpntO,EThndl.buffer.peekN('gaze',nLiveDataPoint),dataWindowDur,eyeColors{:},4,winRectO(3:4));
        Screen('Flip',wpntO);
    end
    
    % repeat the above but show a different image. lets also record some
    % eye images, if supported on connected eye tracker
    if EThndl.buffer.hasStream('eyeImage')
       EThndl.buffer.start('eyeImage');
    end
    % 1. fixation point
    Screen('gluDisk',wpntP,fixClrs(1),winRectP(3)/2,winRectP(4)/2,round(winRectP(3)/100));
    startT      = Screen('Flip',wpntP,nextFlipT);
    EThndl.sendMessage('FIX ON',startT);
    nextFlipT   = startT+fixTime-1/hz/2;
    while nextFlipT-GetSecs()>2/hz   % arbitrarily decide two frames is enough headway
        Screen('gluDisk',wpntO,fixClrs(1),winRectO(3)/2,winRectO(4)/2,round(winRectO(3)/100));
        drawLiveData(wpntO,EThndl.buffer.peekN('gaze',nLiveDataPoint),dataWindowDur,eyeColors{:},4,winRectO(3:4));
        Screen('Flip',wpntO);
    end
    % 2. image
    stimFNameBlur   = 'konijntjes1024x768blur.jpg';
    stimFullNameBlur= fullfile(stimDir,stimFNameBlur);
    im              = imread(stimFullNameBlur);
    tex             = Screen('MakeTexture',wpntP,im);
    Screen('DrawTexture',wpntP,tex);                    % draw centered on the screen
    imgT = Screen('Flip',wpntP,nextFlipT);   % bit of slack to make sure requested presentation time can be achieved
    EThndl.sendMessage(sprintf('STIM ON: %s',stimFNameBlur),imgT);
    nextFlipT = imgT+imageTime-1/hz/2;
    while nextFlipT-GetSecs()>2/hz   % arbitrarily decide two frames is enough headway
        Screen('DrawTexture',wpntO,tex);
        drawLiveData(wpntO,EThndl.buffer.peekN('gaze',nLiveDataPoint),dataWindowDur,eyeColors{:},4,winRectO(3:4));
        Screen('Flip',wpntO);
    end
    
    % 3. end recording after x seconds of data again, clear screen.
    endT = Screen('Flip',wpntP,nextFlipT);
    EThndl.sendMessage(sprintf('STIM OFF: %s',stimFNameBlur),endT);
    Screen('Close',tex);
    Screen('Flip',wpntO);
    
    % stop recording
    if EThndl.buffer.hasStream('eyeImage')
        EThndl.buffer.stop('eyeImage');
    end
    EThndl.buffer.stop('gaze');
    
    % save data to mat file, adding info about the experiment
    dat = EThndl.collectSessionData();
    dat.expt.winRect = winRectP;
    dat.expt.stimDir = stimDir;
    save(EThndl.getFileName(fullfile(cd,'t'), true),'-struct','dat');
    % NB: if you don't want to add anything to the saved data, you can use
    % EThndl.saveData directly
    
    % shut down
    EThndl.deInit();
catch me
    sca
    ListenChar(0);
    rethrow(me)
end
sca
