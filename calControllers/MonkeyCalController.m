classdef MonkeyCalController < handle
    properties (Access=private, Constant)
        stateEnum = struct('cal_positioning',0, 'cal_gazing',1, 'cal_calibrating',2, 'cal_done',3);
    end
    properties (SetAccess=private)
        % state
        stage;

        gazeOnScreen;                               % true if we have gaze for both eyes and the average position is on screen
        meanGaze;
        onScreenTimestamp;                          % time of start of episode of gaze on screen
        offScreenTimestamp;                         % time of start of episode of gaze off screen
        onVideoTimestamp;                           % time of start of episode of gaze on video (for calibration)
        latestTimestamp;                            % latest gaze timestamp

        onScreenTimeThresh;
        videoSize;

        calPoint;
    end
    properties
        % comms
        EThndl;
        calDisplay;
        rewardProvider;

        gazeFetchDur                = 100;          % duration of gaze samples to peek on each iteration (ms, e.g., last 100 ms of gaze)
        scrRes;

        maxOffScreenTime            = 40/60*1000;
        onScreenTimeThreshCap       = 400;          % maximum time animal will be required to keep gaze onscreen for rewards
        onScreenTimeThreshIncRate   = 0.01;         % chance to increase onscreen time threshold

        videoShrinkTime             = 1000;         % how long eyes on video before video shrinks
        videoShrinkRate             = 0.01;         % chance to decrease video size
        
        videoSizes                  = [
                                    1600 1600;
                                    1200 1200;
                                    800 800;
                                    600 600;
                                    500 500;
                                    400 400;
                                    300 300;
                                    ];

        calOnVideoTime              = 500;
        calOnVideoDistFac           = 1/3;          % max gaze distance to be considered close enough to a point to attempt calibration (factor of vertical size of screen)
        calPoints                   = [];           % ID of calibration points to run by the controller, in provided order
        calPoss                     = [];           % corresponding positions
    end
    properties (Access=private,Hidden=true)
        controlState;
        shouldUpdateStatusText;

        awaitingCalResult           = 0;            % 0: not awaiting anything; 1: awaiting point collect result; 2: awaiting point discard result; 3: awaiting compute and apply result
        lastUpdate                  = {};

        drawState                   = 0;            % 0: don't issue draws from here; 1: new command should be given to drawer; 2: regular draw command should be given
    end
    
    
    methods
        function obj = MonkeyCalController(EThndl,calDisplay,scrRes,rewardProvider)
            obj.setCleanState();
            obj.EThndl = EThndl;
            obj.calDisplay = calDisplay;
            if nargin>2
                obj.scrRes = scrRes;
            end
            if nargin>3
                obj.rewardProvider = rewardProvider;
            end
        end

        function commands = tick(obj)
            commands = {};
            obj.updateGaze();
            offScreenTime = obj.latestTimestamp-obj.offScreenTimestamp;
            if strcmp(obj.stage,'cal')
                if offScreenTime > obj.maxOffScreenTime
                    obj.reward(false);
                else
                    if obj.onScreenTimeThresh < obj.onScreenTimeThreshCap
                        % training to position and look at screen
                        obj.trainLookScreen();
                    elseif obj.videoSize < size(obj.videoSizes,1)
                        % training to look at video
                        if obj.controlState ~= obj.stateEnum.cal_gazing
                            obj.drawState = 1;
                            obj.controlState = obj.stateEnum.cal_gazing;
                            obj.shouldUpdateStatusText = true;
                        end
                        obj.trainLookVideo();
                    else
                        % calibrating
                        if obj.controlState ~= obj.stateEnum.cal_calibrating
                            obj.drawState = 1;
                            obj.controlState = obj.stateEnum.cal_calibrating;
                            obj.shouldUpdateStatusText = true;
                        end
                        commands = obj.calibrate();
                    end
                end
            end
        end

        function receiveUpdate(obj,~,currentPoint,posNorm,~,~,type,callResult)
            % event communicated to the controller:
            switch type
                % cal/val mode switches
                case 'cal_enter'
                    obj.stage = 'cal';
                case 'val_enter'
                    obj.stage = 'val';
                % calibration/validation point collected
                case {'cal_collect','val_collect'}
                    {type,currentPoint,posNorm,callResult}
                    obj.lastUpdate = {type,currentPoint,posNorm,callResult};
                % calibration/validation point discarded
                case {'cal_discard','val_discard'}
                    obj.lastUpdate = {type,currentPoint,posNorm,callResult};
                % new calibration computed (may have failed) or loaded
                case 'cal_compute_and_apply'
                    obj.lastUpdate = {type,callResult};
                case 'cal_load'
                    % ignore
                % interface exited from calibration or validation screen
                case {'cal_finished','val_finished'}
                    % we're done according to operator, clear
                    obj.setCleanState();
            end
        end

        function txt = getStatusText(obj)
            txt = '';
            if ~obj.shouldUpdateStatusText
                return
            end
            switch obj.controlState
                case obj.stateEnum.cal_positioning
                    txt = sprintf('Positioning %d/%d',obj.onScreenTimeThresh, obj.onScreenTimeThreshCap);
                case obj.stateEnum.cal_gazing
                    % draw video rect
                    txt = sprintf('Gaze training\nvideo size %d/%d',obj.videoSize,size(obj.videoSizes,1));
                case obj.stateEnum.cal_calibrating
                    txt = sprintf('Calibrating %d/%d',obj.calPoint,length(obj.calPoints));
            end
            obj.shouldUpdateStatusText = false;
        end

        function draw(obj,wpnts,tick,sFac,offset)
            % wpnts: two window pointers. first is for participant screen,
            % second for operator
            if obj.drawState>0
                drawCmd = 'draw';
                if obj.drawState==1
                    drawCmd = 'new';
                    if obj.controlState == obj.stateEnum.cal_positioning
                        obj.calDisplay.calSize = obj.videoSizes(1,:);
                    end
                end
                if ismember(obj.controlState, [obj.stateEnum.cal_positioning obj.stateEnum.cal_gazing])
                    pos = obj.scrRes/2;
                elseif obj.controlState == obj.stateEnum.cal_calibrating
                    calPos = obj.calPoss(obj.calPoint,:).*obj.scrRes(:).';
                    pos = calPos;
                end
                % TODO: don't call draw here if we issued a point command
                % and haven't gotten a status update yet, then code is
                % showing the point
                obj.calDisplay.doDraw(wpnts(1),drawCmd,nan,pos,tick,obj.stage);
                obj.drawState = 2;
            end
            % sFac and offset are used to scale from participant screen to
            % operator screen, in case they have different resolutions
            switch obj.controlState
                case obj.stateEnum.cal_positioning
                    % nothing to draw
                case obj.stateEnum.cal_gazing
                    % draw video rect
                    rect = CenterRectOnPointd([0 0 obj.videoSizes(obj.videoSize,:)*sFac],obj.scrRes(1)/2*sFac+offset(1),obj.scrRes(2)/2*sFac+offset(2));
                    Screen('FrameRect',wpnts(end),0,rect,4);
                case obj.stateEnum.cal_calibrating
                    calPos = obj.calPoss(obj.calPoint,:).*obj.scrRes(:).';
                    rect = CenterRectOnPointd([0 0 obj.videoSizes(obj.videoSize,:)*sFac],calPos(1)*sFac+offset(1),calPos(2)*sFac+offset(2));
                    Screen('FrameRect',wpnts(end),0,rect,4);
            end
        end
    end

    methods (Static)
        function canDo = canControl(type)
            switch type
                case 'calibration'
                    canDo = true;
                case 'validation'
                    canDo = false;
                otherwise
                    error('MonkeyCalController: controller capability "%s" not understood',type)
            end
        end
    end
    
    methods (Access = private, Hidden)
        function setCleanState(obj)
            obj.controlState = obj.stateEnum.cal_positioning;
            obj.shouldUpdateStatusText = true;

            obj.stage = [];
            obj.gazeOnScreen = false;
            obj.meanGaze = [nan nan].';
            obj.onScreenTimestamp = nan;
            obj.offScreenTimestamp = nan;
            obj.onVideoTimestamp = nan;
            obj.latestTimestamp = nan;

            obj.onScreenTimeThresh = 1;
            obj.videoSize = 1;

            obj.calPoint = 1;
            obj.awaitingCalResult = 0;

            obj.drawState = 1;
        end

        function updateGaze(obj)
            gaze = obj.EThndl.buffer.peekN('gaze',round(1000/obj.gazeFetchDur*obj.EThndl.frequency));
            if isempty(gaze)
                return
            end

            minValidFrac = .5;

            obj.latestTimestamp = double(gaze.systemTimeStamp(end))/1000;   % us -> ms
            fValid = mean([gaze.left.gazePoint.valid; gaze.right.gazePoint.valid],2);
            if any(fValid>minValidFrac)
                l_gaze = mean(gaze. left.gazePoint.onDisplayArea(:,gaze. left.gazePoint.valid),2,'omitnan');
                r_gaze = mean(gaze.right.gazePoint.onDisplayArea(:,gaze.right.gazePoint.valid),2,'omitnan');
                obj.meanGaze = mean([l_gaze r_gaze],2).*obj.scrRes(:);
                obj.gazeOnScreen = obj.meanGaze(1) > 0 && obj.meanGaze(1)<obj.scrRes(1) && ...
                                   obj.meanGaze(2) > 0 && obj.meanGaze(2)<obj.scrRes(2);
                if obj.gazeOnScreen
                    obj.offScreenTimestamp = nan;
                    if isnan(obj.onScreenTimestamp)
                        iSamp = find(any([gaze.left.gazePoint.valid; gaze.right.gazePoint.valid],1),1,'last');
                        obj.onScreenTimestamp = double(gaze.systemTimeStamp(iSamp))/1000;   % us -> ms
                    end
                end
            else
                obj.gazeOnScreen = false;
                obj.meanGaze = [nan nan].';
                obj.onScreenTimestamp = nan;
                if isnan(obj.offScreenTimestamp)
                    obj.offScreenTimestamp = double(gaze.systemTimeStamp(1))/1000;  % us -> ms
                end
            end
        end

        function reward(obj,on)
            if isempty(obj.rewardProvider)
                return
            end
            if on
                obj.rewardProvider.start();
            else
                obj.rewardProvider.stop();
            end
        end

        function trainLookScreen(obj)
            onScreenTime = obj.latestTimestamp-obj.onScreenTimestamp;
            % looking long enough on the screen, provide reward
            if onScreenTime > obj.onScreenTimeThresh
                obj.reward(true);
            end
            % if looking much longer than current looking threshold,
            % possibly increase threshold
            if onScreenTime > obj.onScreenTimeThresh*2
                if rand()<=obj.onScreenTimeThreshIncRate
                    obj.onScreenTimeThresh = min(obj.onScreenTimeThresh*2,obj.onScreenTimeThreshCap);   % limit to onScreenTimeThreshCap
                    obj.shouldUpdateStatusText = true;
                end
            end
        end

        function trainLookVideo(obj)
            onScreenTime = obj.latestTimestamp-obj.onScreenTimestamp;
            if onScreenTime > obj.onScreenTimeThresh
                % check distance to center of video (which is always at
                % center of screen)
                dist = hypot(obj.meanGaze(1)-obj.scrRes(1)/2,obj.meanGaze(2)-obj.scrRes(2)/2);
                % if looking close enough to video, provide reward and
                % possibly decrease video size
                if dist < obj.videoSizes(obj.videoSize,2)*2
                    obj.reward(true);
                    if rand()<=obj.videoShrinkRate
                        obj.videoSize = min(obj.videoSize+1,size(obj.videoSizes,1));
                        obj.calDisplay.calSize = obj.videoSizes(obj.videoSize,:);
                        obj.shouldUpdateStatusText = true;
                    end
                else
                    obj.reward(false);
                end
            end
        end

        function commands = calibrate(obj)
            % TODO: needs logic to wait for results of commands
            % TODO: needs to issue compute and apply when all points
            % acquired, and wait for result
            commands = {};
            calPos = obj.calPoss(obj.calPoint,:).*obj.scrRes(:).';
            dist = hypot(obj.meanGaze(1)-calPos(1),obj.meanGaze(2)-calPos(2));
            if obj.awaitingCalResult>0
                % we're waiting for the result of an action. Those are all
                % blocking in the Python code, but not here. For identical
                % behavior (and easier logic), we put all the response
                % waiting logic here, short-circuiting the below logic that
                % depends on where the subject looks
                if isempty(obj.lastUpdate)
                    return;
                end
                if obj.awaitingCalResult==1 && strcmp(obj.lastUpdate{1},'cal_collect')
                    % check this is for the expected point
                    if obj.lastUpdate{2}==obj.calPoints(obj.calPoint) && all(obj.lastUpdate{3}==obj.calPoss(obj.calPoint,:))
                        % check result
                        if obj.lastUpdate{4}.status==0     % TOBII_RESEARCH_STATUS_OK
                            % success, decide next action
                            if obj.calPoint<length(obj.calPoints)
                                % calibrate next point
                                obj.calPoint = obj.calPoint+1;
                                obj.awaitingCalResult = 0;
                                obj.shouldUpdateStatusText = true;
                                obj.onVideoTimestamp = nan;
                                obj.drawState = 1;
                            else
                                % all collected, attempt calibration
                                commands = {{'cal','compute_and_apply'}};
                                obj.awaitingCalResult = 3;
                                obj.shouldUpdateStatusText = true;
                            end
                        else
                            commands = {{'cal','discard_point', obj.calPoints(obj.calPoint), obj.calPoss(obj.calPoint,:)}};
                            obj.awaitingCalResult = 2;
                        end
                    end
                    obj.lastUpdate = {};
                elseif obj.awaitingCalResult==2 && strcmp(obj.lastUpdate{1},'cal_discard')
                    % check this is for the expected point
                    if obj.lastUpdate{2}==obj.calPoints(obj.calPoint) && all(obj.lastUpdate{3}==obj.calPoss(obj.calPoint,:))
                        if obj.lastUpdate{4}.status==0     % TOBII_RESEARCH_STATUS_OK
                            obj.awaitingCalResult = 0;
                        else
                            error('can''t discard point, something seriously wrong')
                        end
                    end
                    obj.lastUpdate = {};
                elseif obj.awaitingCalResult==3 && strcmp(obj.lastUpdate{1},'cal_compute_and_apply')
                    if obj.lastUpdate{2}.status==0 && strcmpi(obj.lastUpdate{2}.calibrationResult,'success')
                        % successful calibration
                        obj.reward(false);
                        obj.controlState = obj.stateEnum.cal_done;
                        obj.shouldUpdateStatusText = true;
                        commands = {{'cal','disable_controller'}};
                    else
                        % failed, start over
                        for p=length(obj.calPoints):-1:1    % reverse so we can set cal state back to first point and await discard of that first point, will arrive last
                            commands = [commands {{'cal','discard_point', obj.calPoints(p), obj.calPoss(p,:)}}];
                        end
                        obj.awaitingCalResult = 2;
                        obj.calPoint = 1;
                    end
                    obj.lastUpdate = {};
                elseif ~isempty(obj.lastUpdate)
                    % unexpected (perhaps stale, e.g. from before auto was switched on) update, discard
                    obj.lastUpdate = {};
                end
            elseif dist < obj.calOnVideoDistFac*obj.scrRes(2)
                obj.reward(true);
                if obj.onVideoTimestamp<0 || isnan(obj.onVideoTimestamp)
                    obj.onVideoTimestamp = obj.latestTimestamp;
                end
                onDur = obj.latestTimestamp-obj.onVideoTimestamp;
                if onDur > obj.calOnVideoTime
                    if obj.awaitingCalResult==0
                        % request calibration point collection
                        commands = {{'cal','collect_point', obj.calPoints(obj.calPoint), obj.calPoss(obj.calPoint,:)}}; % something with point ID and location, so Titta's logic can double check it knows this point
                        obj.awaitingCalResult = 1;
                    end
                end
            else
                if obj.onVideoTimestamp>0 || isnan(obj.onVideoTimestamp)
                    obj.onVideoTimestamp = -obj.latestTimestamp;
                end
                offDur = obj.latestTimestamp--obj.onVideoTimestamp;
                if offDur > obj.maxOffScreenTime
                    obj.reward(false);
                    % request discarding data for this point
                    commands = {{'cal','discard_point', obj.calPoints(obj.calPoint), obj.calPoss(obj.calPoint,:)}};
                    obj.awaitingCalResult = 2;
                end
            end
        end
    end
end
