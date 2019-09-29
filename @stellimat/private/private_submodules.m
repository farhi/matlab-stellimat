function c = private_submodules(self)
  % PRIVATE_SUBMODULES check/install submodules for dependencies
  
  c = {};

  d = fileparts(fileparts(which('stellimat')));  % dir above class
  for sub = dir(fullfile(d, 'matlab-*'))';        % submodules
    add = true;
    class_name = sub.name;
    if ~exist(class_name(8:end))
      disp(fullfile(d, class_name))
      addpath(fullfile(d, class_name));
      % check for success
      if ~exist(class_name(8:end))
        disp([ class(self) ': WARNING: "' class_name(8:end) '" dependency can not be found.' ])
        disp('*** Use "git submodule init", then "git submodule update" to import it.')
        add = false;
      end
    end
    if add, c{end+1} = class_name(8:end); end
  end
    
end % private_submodules
