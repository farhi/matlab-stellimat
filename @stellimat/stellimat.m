classdef stellimat < handle
% STELLIMAT Automatic mount/camera handling for astrophotography.
%   STELLIMAT Alone will search for a camera and mount to connect to.
%
%   STELLIMAT('usb:XX,YY','/dev/ttyUSB0') connects to given gPhoto2 and StarGo ports.
%
%   STELLIMAT(gphoto(..), stargo(..)) connects to given gPhoto and mount objects,
%   which can be given as gphoto, sonyalpha stargo or starbook classes.

  properties
    mount       = []; % the mount object,  e.g. stargo, starbook
    camera      = []; % the camera object, e.g. gphoto, sonyalpha
    astrometry  = []; % the astrometry object
    
    private     = []; % internal stuff. do not touch.
    catalogs    = [];
  end %properties

  properties (Constant=true)
    submodules = private_submodules;
  end % private properties

  methods
    function self = stellimat(varargin)  % (..., object, mount_port, camera_port)
      % STELLIMAT Start the StelliMat automatic scope control.   
    
      % start all objects
      % ------------------------------------------------------------------------
      
      % first scan input arguments (objects)
      for index=1:nargin
        switch class(varargin{index})
        case {'gphoto','sonyalpha'}
          self.camera = varargin{index};
        case {'stargo','starbook'}
          self.mount  = varargin{index};
        case {'astrometry'}
          self.astrometry = varargin{index};
        case 'char'
          if any(strcmp(strtok(varargin{index},':'),{'serial','usb','ptpip'})) && exist('gphoto')
            self.camera = gphoto(varargin{index});
          elseif any(strcmp(strtok(varargin{index},':'),{'http','https','ftp'})) && exist('sonyalpha')
            self.camera = sonyalpha(varargin{index}); % HTTP could also be a StarBook IP
          elseif strncmp(varargin{index}, 'sim', 3)
            self.camera = gphoto('sim');
            self.mount  = stargo('sim');
          elseif strncmp(varargin{index}, 'COM', 3) || strncmp(varargin{index}, '/dev/', 5)
            self.mount  = stargo(varargin{index});
          end
        end
      end

      % camera, with process. could use: sonyalpha.
      if isempty(self.camera)
        if exist('sonyalpha')
          self.camera     = sonyalpha; % IP
        elseif exist('gphoto')
          self.camera     = gphoto;    % port
        else
          disp([ mfilename ': can not find any camera (gphoto, sonyalpha).' ])
        end
      end

      % mount, with skychart. could use starbook
      if isempty(self.mount)
        if exist('starbook')
          self.mount      = starbook;
        elseif exist('stargo')
          self.mount      = stargo; % port                           
        else
          disp([ mfilename ': can not find any mount (stargo, starbook).' ])
        end
      end
      if ~isempty(self.mount) && isobject(self.mount) && ismethod(self.mount, 'get_catalogs')
        plot(self.mount); % display so that we can import the catalogs
        self.catalogs = get_catalogs(self.mount);
      end

      % astrometry, using loaded catalogs.
      if isempty(self.astrometry)
        if exist('astrometry')
          if ~isempty(self.catalogs)
            self.astrometry = astrometry('/dev/null','catalogs', self.catalogs, 'scale-low', 0.5, 'scale-high',2);
          else
            self.astrometry = astrometry('/dev/null','scale-low', 0.5, 'scale-high',2);
          end
        else
          disp([ mfilename ': can not find any astrometry tool.' ])
        end
      end
      if isempty(self.catalogs) && ~isempty(self.astrometry) && isobject(self.astrometry) ...
        && ismethod(self.astrometry, 'get_catalogs')
        self.catalogs = get_catalogs(self.astrometry);
      end
      
      % actions
      % ------------------------------------------------------------------------
      
      % when camera has captured an image, trigger astrometry on it
      % the camera should be e.g. in time-lapse mode: continuous(camera,'on')
      % >> condition: astrometry must be idle
      addlistener(self.camera, 'captureStop', @(src,evnt)CallBack_annotate(self));
      
      % when astrometry ends, indicate its position on the SkyChart
      % >> condition: astrometry result is not empty (success)
      addlistener(self.astrometry, 'annotationEnd', @(srv,evnt)CallBack_show_real_position(self));
      
      plot(self);
    end % stellimat instantiate
    
    function locate(self, img)
      % LOCATE Determine the RA/DEC coordinates of a given image file
      %   LOCATE(s) captures an image from the camera and determines its
      %   coordinates.
      %
      %   LOCATE(s, img) determines the given image coordinates.
      if strcmpi(self.astrometry.status, 'running')
        return
      end
      if nargin < 2 || isempty(img)
        capture(self.camera);
      else
        disp([ mfilename ': starting annotation of ' img ]);
        self.private.lastImageFile = img;
        local(self.astrometry, img); % launch annotation
      end
    end % locate
    
    function plot(self)
      % PLOT Plot the Mount GUI
      plot(self.mount);
    end % plot
    
    function st = get_state(self)
      % GET_STATE Get the Stellimat state
      st = '';
      objects = {self.camera self.mount self.astrometry};
      names   = {'Camera','Mount','Astrometry'};
      for index = 1:numel(objects)
        o = objects{index};
        if ~isobject(o) || ~isvalid(o), continue; end
        val = [];
        if ismethod(o, 'get_state')
          val = get_state(o);
        elseif ismethod(o, 'getstatus')
          val = getstatus(o);
        end
        if isempty(val), try; val = o.status; end; end
        if isempty(val), try; val = o.state;  end; end
        if isempty(val) continue; end
        if isnumeric(val) val=num2str(val); end
        st = [ st names{index} ':' val ' ' ];
      end
    end % get_state
    
    function st = getstatus(self)
      % GETSTATUS Get the Stellimat state
      st = get_state(self);
    end % getstatus

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
  if strcmpi(get_state(self.astrometry), 'running')
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
    self.private.lastImageFile = img{1};
    local(self.astrometry, fullfile(self.camera.dir, img{1})); % launch annotation
  end
end % CallBack_annotate

function CallBack_show_real_position(self)
  % CallBack_show_real_position when astrometry ends, indicate its position on the SkyChart
  % >> condition: astrometry result is not empty (success)
  if ~isempty(self.astrometry.result)
    % show real scope RA/DEC coords in mount skychart.
    disp([ mfilename ': the image ' self.private.lastImageFile ' RA/DEC location is: ' ...
      self.astrometry.result.RA_hms ' ' self.astrometry.result.Dec_dms ]);
    % plot cross on th StarGo skychart
    h = findall(0, 'Tag', 'Stellimat_astrometry_stargo');
    if ~isempty(h), delete(h); end
    h = scatter(self.mount, self.astrometry.result.RA, self.astrometry.result.Dec);
    set(h, 'Tag', 'Stellimat_astrometry_stargo');
    % display annotation on image
    fig = findall(0, 'Tag','Stellimat_astrometry_fig'); % any previous astrometry plot to replace ?
    if ~isempty(fig), pos = get(fig, 'Position'); close(fig); else pos = []; end
    fig = plot(self.astrometry);
    if ~isempty(pos)
      set(fig, 'Tag','Stellimat_astrometry_fig', 'Position', pos);
    else
      set(fig, 'Tag','Stellimat_astrometry_fig');
    end
  else
    disp([ mfilename ': the image ' self.private.lastImageFile ' RA/DEC annotation FAILED.' ])
  end
  % now may correct for misalignment when mount is idle and option is set.
end % CallBack_show_real_position
