% start all objects
% ------------------------------------------------------------------------------

% camera, with process. could use: sonyalpha.
camera  = gphoto;                                  

% mount, with skychart. could use starbook.
mount = stargo;                                  

% astrometry, using loaded catalogs.
as = astrometry('','catalogs', sg.catalogs);  


% actions
% ------------------------------------------------------------------------------

% when camera has captured an image, trigger astrometry on it
% the camera should be e.g. in time-lapse mode: continuous(camera,'on')
% >> condition: astrometry must be idle
addlistener(camera, 'captureStop', @(src,evnt)local(as, camera.lastImageFile{1}));

% when astrometry ends, indicate its position on the SkyChart
addlistener(as, 'annotationEnd', @(srv,evnt)scatter(mount, as.results.RA, as.result.Dec));

% when astrometry ends, and mount idle, compensate for shift (when small enough)
% then align/sync when not already done so (+/- 5deg), and far from RA/DEC boundaries
%   mount thinks it is in [ mount.get_ra('deg') mount.get_dec('deg') ]
%   the real location is  [ as.result.RA        as.result.Dec('deg') ]
%     target_RA = 2*target_RA-real_RA   in [deg]
%     target_DEC= 2*target_DEC-real_DEC in [deg].
% >> condition: mount idle
addlistener(as, 'annotationEnd', @(src,evnt)shift(mount, ...
  2*mount.get_ra('deg') - as.result.RA, ...
  2*mount.get_dec('deg')- as.result.Dec));
% >> condition: mount idle, after shift
addlistener(mount, 'idle', @(src,evnt)align(mount)); % after shift  
