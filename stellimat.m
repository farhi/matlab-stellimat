classdef stellimat < handle
% STELLIMAT Automatic mount/camera handling for astrophotography.

properties
  mount       = []; % the mount object,  e.g. stargo, starbook
  camera      = []; % the camera object, e.g. gphoto, sonyalpha
  astrometry  = []; % the astrometry object
  
  private     = []; % internal stuff. do not touch.
end %properties

methods
  function self = stellimat(varargin)  % (..., object, mount_port, camera_port)
    % start all objects
    % ------------------------------------------------------------------------------
    
    % first scan input arguments (objects)
    for index=1:nargin
      switch class(varargin{index})
      case {'gphoto','sonyalpha'}
        self.camera = varargin{index};
      case {'stargo','starbook'}
        self.mount  = varargin{index};
      case {'astrometry'}
        self.astrometry = varargin{index};
      end
    end

    % camera, with process. could use: sonyalpha.
    if isempty(self.camera)
      if exist('gphoto')
        self.camera     = gphoto; % port
      elseif exist('sonyalpha')
        self.camera     = sonyalpha;
      end
    end

    % mount, with skychart. could use starbook
    if isempty(self.mount)
      if exist('stargo')
        self.mount      = stargo; % port                           
      elseif exist('starbook')
        self.mount      = starbook;
      end
    end

    % astrometry, using loaded catalogs.
    if isempty(self.astrometry)
      self.astrometry = astrometry('/dev/null','catalogs', self.mount.private.skychart.catalogs, ...
        'scale-low', 0.5, 'scale-high',2); 
    end
    
    % actions
    % -------
    
    % when camera has captured an image, trigger astrometry on it
    % the camera should be e.g. in time-lapse mode: continuous(camera,'on')
    % >> condition: astrometry must be idle
    addlistener(self.camera, 'captureStop', @(src,evnt)CallBack_annotate(self));
    
    % when astrometry ends, indicate its position on the SkyChart
    % >> condition: astrometry result is not empty (success)
    addlistener(self.astrometry, 'annotationEnd', @(srv,evnt)CallBack_show_real_position(self));
  end % stellimat instantiate

end % methods

end % classdef
% actions
% ------------------------------------------------------------------------------



% when astrometry ends, and mount idle, compensate for shift (when small enough)
% then align/sync when not already done so (+/- 5deg), and far from RA/DEC boundaries
%   mount thinks it is in [ mount.get_ra('deg') mount.get_dec('deg') ]
%   the real location is  [ as.result.RA        as.result.Dec('deg') ]
%     target_RA = 2*target_RA-real_RA   in [deg]
%     target_DEC= 2*target_DEC-real_DEC in [deg].
% >> condition: mount idle

%addlistener(as, 'annotationEnd', @(src,evnt)shift(mount, ...
%  2*mount.get_ra('deg') - as.result.RA, ...
%  2*mount.get_dec('deg')- as.result.Dec));
  
% >> condition: mount idle, after shift

% addlistener(mount, 'idle', @(src,evnt)align(mount)); % after shift  

% ------------------------------------------------------------------------------

function CallBack_annotate(self)
  % CallBack_annotate when camera has captured an image, trigger astrometry on it
  % the camera should be e.g. in time-lapse mode: continuous(camera,'on')
  % >> condition: astrometry must be idle
  
  % check astrometry is IDLE
  if strcmp(self.astrometry.status, 'running')
    return
  end
  % check camera has produced an image, and its time is more recent that previous
  if ~isfield(self.private, 'lastImageDate'), self.private.lastImageDate = clock*0; end
  img = self.camera.lastImageFile;
  if isempty(img), return; end
  img = cellstr(img);
  if ~isempty(img{1}) && ~isempty(dir(fullfile(self.camera.dir, img{1}))) % image exists
    % check date: must be a new image
    if etime(self.camera.lastImageDate,self.private.lastImageDate) < 1, return; end
    disp([ mfilename ': starting annotation of ' fullfile(self.camera.dir, img{1}) ]);
    local(self.astrometry, fullfile(self.camera.dir, img{1})); % launch annotation
  end
end % CallBack_annotate

function CallBack_show_real_position(self)
  % CallBack_show_real_position when astrometry ends, indicate its position on the SkyChart
  % >> condition: astrometry result is not empty (success)
  if ~isempty(self.astrometry.result)
    % show real scope RA/DEC coords in mount skychart.
    disp([ mfilename ': the image RA/DEC location is:' ...
      self.astrometry.result.RA_hms ' ' self.astrometry.result.Dec_dms ]);
    scatter(self.mount, self.astrometry.results.RA, self.astrometry.result.Dec);
  end
  % now may correct for misalignment when mount is idle and option is set.
end % CallBack_show_real_position
