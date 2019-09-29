function private_submodules(self)
  % PRIVATE_SUBMODULES check/install submodules for dependencies

  d = fileparts(fileparts(which(class(self))));  % dir above class
  for sub = dir(fullfile(d, 'matlab-*'));         % submodules
    class_name = sub.name;
    if ~exist(class_name(8:end))
      addpath(fullfile(d, class_name));
      % check for success
      if ~exist(class_name(8:end))
        disp([ class(self) ': WARNING: "' class_name(8:end) '" dependency can not be found.' ])
        disp('*** Use "git submodule init", then "git submodule update" to import it.'
      end
    end
  end
    
end % private_submodules
