% Please edit this file with the correct paths for ZMQ instalation.

if (ismac)
	% if using apple silicon, install a x86 homebrew first
	ZMQ_COMPILED_LIB = 'libzmq.a';
	ZMQ_LIB_PATH = '/opt/homebrew/Cellar/zeromq/4.3.5_1/lib/';
	ZMQ_INCLUDE_PATH = '/opt/homebrew/Cellar/zeromq/4.3.5_1/include/';
elseif (isunix)
	ZMQ_COMPILED_LIB = 'libzmq.a';
	ZMQ_LIB_PATH = '/usr/lib/x86_64-linux-gnu/';
	ZMQ_INCLUDE_PATH = '/usr/include/';
elseif (ispc)
	ZMQ_COMPILED_LIB = 'libzmq-v120-mt-4_0_4.lib';
	ZMQ_LIB_PATH = 'C:\Program Files\ZeroMQ 4.0.4\lib\';
	ZMQ_INCLUDE_PATH = 'C:\Program Files\ZeroMQ 4.0.4\include';
else
	error("libzmq install paths need to be added to config.m for your platform")
end
