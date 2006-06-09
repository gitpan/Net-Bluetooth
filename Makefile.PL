use ExtUtils::MakeMaker;
use Config qw(%Config);

print "OS = $Config{osname}\n";

WriteMakefile(
    'NAME'	=> 'Net::Bluetooth',
    'VERSION_FROM' => 'Bluetooth.pm', # finds $VERSION
    'LIBS'	=> ['-lbluetooth'],   # e.g., '-lm' 
    'DEFINE'	=> $define,     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
    'XSPROTOARG' => '-prototypes' 
);
