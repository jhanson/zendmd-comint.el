zendmd-comint.el
========

zendmd-comint mode is a drop in replace for the python process in the Emacs editing environment. When you do python development in Emacs you get used to testing bits of functionality
by selecting a certain region or buffer and sending it directly to the interactive python process. This speeds up the development process by providing rapid feedback on your
code changes. This package provides the same functionality to zenoss except instead of sending the code to python it is sent to the zendmd process.

Installing
-----------

Place the zendmd-comint.el somewhere in your load path and add the following lines to your .emacs
    (require 'zendmd-comint)
    (setq inferior-zendmd-program-command "/path/to/zendmd") ;; this may not be necessary if you have zendmd on your PATH
    (add-hook 'python-mode-hook '(lambda ()
                               (zendmd-minor-mode 1))) ;; will activate the minor mode every time you visit a python buffer

At that point you can press C-c C-z (by default) to automatically go to the zendmd.

Features
----------
zendmd provides the following features

* Python syntax highlighting in the zendmd
* Send functions, buffers or regions to the zendmd.
* Automatically load files in the zendmd
* Ability to quickly execute an zendmd python script in a new zendmd process.
* The power of emacs editing when interacting with zendmd

To see all the commands available press C-h b (describe bindings) when you have the minor mode activated and look under the "zendmd-minor-mode" bindings.
