#!/usr/bin/perl

use strict;
use warnings;

use File::Basename;
use Data::Dumper;
use Net::Domain;
use Term::ANSIColor;
use Cwd;

my $GLOBAL_PATH_TO_SCRIPT;
my $GLOBAL_PATH_TO_SCRIPT_DIR;
my $GLOBAL_PATH_TO_TOP;
my $GLOBAL_PATH_TO_BUILDS;

my $GLOBAL_BUILD_NO;
my $GLOBAL_BUILD_TS;
my $GLOBAL_BUILD_DIR;
my $GLOBAL_BUILD_OS;
my $GLOBAL_BUILD_RELEASE;
my $GLOBAL_BUILD_RELEASE_NO;
my $GLOBAL_BUILD_RELEASE_NO_SHORT;
my $GLOBAL_BUILD_RELEASE_CANDIDATE;
my $GLOBAL_BUILD_TYPE;
my $GLOBAL_BUILD_ARCH;
my $GLOBAL_THIRDPARTY_SERVER;
my $GLOBAL_BUILD_PROD_FLAG;
my $GLOBAL_BUILD_DEBUG_FLAG;


BEGIN
{
   $GLOBAL_PATH_TO_SCRIPT     = Cwd::abs_path(__FILE__);
   $GLOBAL_PATH_TO_SCRIPT_DIR = dirname($GLOBAL_PATH_TO_SCRIPT);
   $GLOBAL_PATH_TO_TOP        = dirname($GLOBAL_PATH_TO_SCRIPT_DIR);
}

chdir($GLOBAL_PATH_TO_TOP);

##############################################################################################

main();

##############################################################################################

sub main
{
   InitGlobalBuildVars();
   Prepare();
   Checkout("public_repos.pl");
   Checkout("private_repos.pl") if ( $GLOBAL_BUILD_TYPE eq "NETWORK" );
   Build();
}

sub InitGlobalBuildVars()
{
   if ( -f "/tmp/last.build_no_ts" && $ENV{ENV_RESUME_FLAG} )
   {
      my $x = LoadProperties("/tmp/last.build_no_ts");

      $GLOBAL_BUILD_NO = $x->{BUILD_NO};
      $GLOBAL_BUILD_TS = $x->{BUILD_TS};
   }

   $GLOBAL_BUILD_NO ||= GetNewBuildNo();
   $GLOBAL_BUILD_TS ||= GetNewBuildTs();

   my $build_cfg = LoadProperties("$GLOBAL_PATH_TO_SCRIPT_DIR/build.config");

   $GLOBAL_PATH_TO_BUILDS          = $build_cfg->{PATH_TO_BUILDS}          || "$GLOBAL_PATH_TO_TOP/BUILDS";
   $GLOBAL_BUILD_RELEASE           = $build_cfg->{BUILD_RELEASE}           || Die("config not specified BUILD_RELEASE");
   $GLOBAL_BUILD_RELEASE_NO        = $build_cfg->{BUILD_RELEASE_NO}        || Die("config not specified BUILD_RELEASE_NO");
   $GLOBAL_BUILD_RELEASE_CANDIDATE = $build_cfg->{BUILD_RELEASE_CANDIDATE} || Die("config not specified BUILD_RELEASE_CANDIDATE");
   $GLOBAL_BUILD_TYPE              = $build_cfg->{BUILD_TYPE}              || Die("config not specified BUILD_TYPE");
   $GLOBAL_THIRDPARTY_SERVER       = $build_cfg->{THIRDPARTY_SERVER}       || Die("config not specified THIRDPARTY_SERVER");
   $GLOBAL_BUILD_PROD_FLAG         = $build_cfg->{BUILD_PROD_FLAG}         || "true";
   $GLOBAL_BUILD_DEBUG_FLAG        = $build_cfg->{BUILD_DEBUG_FLAG}        || "false";
   $GLOBAL_BUILD_OS                = GetBuildOS();
   $GLOBAL_BUILD_ARCH              = GetBuildArch();

   s/[.]//g for ( $GLOBAL_BUILD_RELEASE_NO_SHORT = $GLOBAL_BUILD_RELEASE_NO );

   $GLOBAL_BUILD_DIR = "$GLOBAL_PATH_TO_BUILDS/$GLOBAL_BUILD_OS/$GLOBAL_BUILD_RELEASE-$GLOBAL_BUILD_RELEASE_NO_SHORT/${GLOBAL_BUILD_TS}_$GLOBAL_BUILD_TYPE";

   my $cc    = DetectPrerequisite("cc");
   my $cpp   = DetectPrerequisite("c++");
   my $java  = DetectPrerequisite( "java", $ENV{JAVA_HOME} ? "$ENV{JAVA_HOME}/bin" : "" );
   my $javac = DetectPrerequisite( "javac", $ENV{JAVA_HOME} ? "$ENV{JAVA_HOME}/bin" : "" );
   my $mvn   = DetectPrerequisite("mvn");
   my $ant   = DetectPrerequisite("ant");
   my $ruby  = DetectPrerequisite("ruby");

   $ENV{JAVA_HOME} ||= dirname( dirname( Cwd::realpath($javac) ) );
   $ENV{PATH} = "$ENV{JAVA_HOME}/bin:$ENV{PATH}";

   my $fmt2v = " %-35s: %s\n";

   print "=========================================================================================================\n";
   foreach my $x (`grep -o '\\<GLOBAL[_][A-Z_]*\\>' $GLOBAL_PATH_TO_SCRIPT | sort | uniq`)
   {
      chomp($x);
      printf( $fmt2v, $x, eval "\$$x" );
   }

   print "=========================================================================================================\n";
   foreach my $x (`grep -o '\\<[E][N][V]_[A-Z_]*\\>' $GLOBAL_PATH_TO_SCRIPT | sort | uniq`)
   {
      chomp($x);
      printf( $fmt2v, $x, defined $ENV{$x} ? $ENV{$x} : "(undef)" );
   }

   print "=========================================================================================================\n";
   printf( $fmt2v, "USING javac", "$javac (JAVA_HOME=$ENV{JAVA_HOME})" );
   printf( $fmt2v, "USING java", $java );
   printf( $fmt2v, "USING maven", $mvn );
   printf( $fmt2v, "USING ant", $ant );
   printf( $fmt2v, "USING cc", $cc );
   printf( $fmt2v, "USING c++", $cpp );
   printf( $fmt2v, "USING ruby", $ruby );
   print "=========================================================================================================\n";
   print "Press enter to proceed";

   read STDIN, $_, 1;
}

sub Prepare()
{
   system( "rm", "-rf", "$ENV{HOME}/.zcs-deps" )   if ( $ENV{ENV_CACHE_CLEAR_FLAG} );
   system( "rm", "-rf", "$ENV{HOME}/.ivy2/cache" ) if ( $ENV{ENV_CACHE_CLEAR_FLAG} );

   open( FD, ">", "/tmp/last.build_no_ts" );
   print FD "BUILD_NO=$GLOBAL_BUILD_NO\n";
   print FD "BUILD_TS=$GLOBAL_BUILD_TS\n";
   close(FD);

   System( "mkdir", "-p", "$GLOBAL_BUILD_DIR" );
   System( "mkdir", "-p", "$GLOBAL_BUILD_DIR/logs" );
   System( "mkdir", "-p", "$ENV{HOME}/.zcs-deps" );
   System( "mkdir", "-p", "$ENV{HOME}/.ivy2/cache" );

   my @TP_JARS = (
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/ant-1.7.0-ziputil-patched.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/ant-contrib-1.0b1.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/ews_2010-1.0.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/jruby-complete-1.6.3.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/plugin.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/servlet-api-3.1.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/unboundid-ldapsdk-2.3.5-se.jar",
      "http://$GLOBAL_THIRDPARTY_SERVER/ZimbraThirdParty/third-party-jars/zimbrastore-test-1.0.jar",
   );

   for my $j_url (@TP_JARS)
   {
      if ( my $f = "$ENV{HOME}/.zcs-deps/" . basename($j_url) )
      {
         if ( !-f $f )
         {
            System("wget '$j_url' -O '$f.tmp'");
            System("mv '$f.tmp' '$f'");
         }
      }
   }
}

sub Checkout($)
{
   my $repo_file = shift;

   if ( !-d "zimbra-package-stub" )
   {
      System( "git", "clone", "https://github.com/Zimbra/zimbra-package-stub.git" );
   }

   if ( !-d "junixsocket" )
   {
      System( "git", "clone", "-b", "junixsocket-parent-2.0.4", "https://github.com/kohlschutter/junixsocket.git" );
   }

   if ( -f "$GLOBAL_PATH_TO_TOP/zm-build/$repo_file" )
   {
      my @REPOS = ();
      eval `cat $GLOBAL_PATH_TO_TOP/zm-build/$repo_file`;
      Die("Error in $repo_file)", "$@") if ($@);

      for my $repo_details (@REPOS)
      {
         Clone($repo_details);
      }
   }
}

sub Build()
{
   my @ALL_BUILDS;
   eval `cat $GLOBAL_PATH_TO_TOP/zm-build/global_builds.pl`;
   Die("Error in global_builds.pl", "$@") if ($@);

   my @ant_attributes = (
      "-Ddebug=${GLOBAL_BUILD_DEBUG_FLAG}",
      "-Dis-production=${GLOBAL_BUILD_PROD_FLAG}",
      "-Dzimbra.buildinfo.platform=${GLOBAL_BUILD_OS}",
      "-Dzimbra.buildinfo.version=${GLOBAL_BUILD_RELEASE_NO}_${GLOBAL_BUILD_RELEASE_CANDIDATE}_${GLOBAL_BUILD_NO}",
      "-Dzimbra.buildinfo.type=${GLOBAL_BUILD_TYPE}",
      "-Dzimbra.buildinfo.release=${GLOBAL_BUILD_TS}",
      "-Dzimbra.buildinfo.date=${GLOBAL_BUILD_TS}",
      "-Dzimbra.buildinfo.host=@{[Net::Domain::hostfqdn]}",
      "-Dzimbra.buildinfo.buildnum=${GLOBAL_BUILD_RELEASE_NO}",
   );

   my $cnt = 0;
   for my $build_info (@ALL_BUILDS)
   {
      ++$cnt;

      if ( my $dir = $build_info->{dir} )
      {
         next
            unless ( !defined $ENV{ENV_BUILD_INCLUDE} || grep { $dir =~ /$_/ } split( ",", $ENV{ENV_BUILD_INCLUDE} ) );

         print "=========================================================================================================\n";
         print color('bright_blue') . "BUILDING: $dir ($cnt of " . scalar(@ALL_BUILDS) . color('reset') . ")\n";
         print "\n";

         unlink glob "$dir/.built.*"
           if ( $ENV{ENV_FORCE_REBUILD} && grep { $dir =~ /$_/ } split( ",", $ENV{ENV_FORCE_REBUILD} ) );

         if ( $ENV{ENV_RESUME_FLAG} && -f "$dir/.built.$GLOBAL_BUILD_TS" )
         {
            print color('bright_yellow') . "WARNING: SKIPPING - to force a rebuild - either delete $dir/.built.$GLOBAL_BUILD_TS or include in ENV_FORCE_REBUILD" . color('reset') . "\n";
            print "=========================================================================================================\n";
            print "\n";
         }
         else
         {
            unlink glob "$dir/.built.*";

            my $force_clean = 1
              if ( !$ENV{ENV_SKIP_CLEAN_FLAG} || -f "$dir/.force-clean" );

            Run(
               cd   => $dir,
               call => sub {

                  my $abs_dir = Cwd::abs_path();

                  eval {
                     s/\/*$//
                       for ( my $sane_dir = $dir );
                     System("cd '$GLOBAL_BUILD_DIR' && rm -rf '$sane_dir'") if ( $force_clean && $sane_dir );
                  };

                  if ( my $ant_targets = $build_info->{ant_targets} )
                  {
                     eval { System( "ant", "clean" ) if ($force_clean); };

                     System( "ant", @ant_attributes, @$ant_targets );
                  }

                  if ( my $mvn_targets = $build_info->{mvn_targets} )
                  {
                     eval { System( "mvn", "clean" ) if ($force_clean); };

                     System( "mvn", @$mvn_targets );
                  }

                  if ( my $make_targets = $build_info->{make_targets} )
                  {
                     eval { System( "make", "clean" ) if ($force_clean); };

                     System( "make", @$make_targets );
                  }

                  if ( my $stage_cmd = $build_info->{stage_cmd} )
                  {
                     &$stage_cmd
                  }
               },
            );

            if ( !exists $build_info->{partial} )
            {
               eval { unlink("$dir/.force-clean"); };

               print "Creating $dir/.built.$GLOBAL_BUILD_TS\n";
               open( FD, "> $dir/.built.$GLOBAL_BUILD_TS" );
               close(FD);
            }

            print "\n";
            print "=========================================================================================================\n";
            print "\n";
         }
      }
   }

   Run(
      cd   => "zm-build",
      call => sub {
         System("(cd .. && rsync -az --delete zm-build $GLOBAL_BUILD_DIR/)");
         System("mkdir -p $GLOBAL_BUILD_DIR/zm-build/$GLOBAL_BUILD_ARCH");

         my @ALL_PACKAGES = ();
         push( @ALL_PACKAGES, @{ GetPackageList("public_packages.pl") } );
         push( @ALL_PACKAGES, @{ GetPackageList("private_packages.pl") } ) if ( $GLOBAL_BUILD_TYPE eq "NETWORK" );
         push( @ALL_PACKAGES, "zcs-bundle" );

         for my $package_script (@ALL_PACKAGES)
         {
            if ( !defined $ENV{ENV_PACKAGE_INCLUDE} || grep { $package_script =~ /$_/ } split( ",", $ENV{ENV_PACKAGE_INCLUDE} ) )
            {
               System(
                  "  release='$GLOBAL_BUILD_RELEASE_NO.$GLOBAL_BUILD_RELEASE_CANDIDATE' \\
                     branch='$GLOBAL_BUILD_RELEASE-$GLOBAL_BUILD_RELEASE_NO_SHORT' \\
                     buildNo='$GLOBAL_BUILD_NO' \\
                     os='$GLOBAL_BUILD_OS' \\
                     buildType='$GLOBAL_BUILD_TYPE' \\
                     repoDir='$GLOBAL_BUILD_DIR' \\
                     arch='$GLOBAL_BUILD_ARCH' \\
                     buildTimeStamp='$GLOBAL_BUILD_TS' \\
                     buildLogFile='$GLOBAL_BUILD_DIR/logs/build.log' \\
                     zimbraThirdPartyServer='$GLOBAL_THIRDPARTY_SERVER' \\
                        bash $GLOBAL_PATH_TO_TOP/zm-build/scripts/packages/$package_script.sh
                  "
               );
            }
         }
      },
   );

   print "\n";
   print "=========================================================================================================\n";
   print "\n";
}


sub GetPackageList($)
{
   my $package_list_file = shift;

   my @PACKAGES = ();

   if ( -f "$GLOBAL_PATH_TO_TOP/zm-build/$package_list_file" )
   {
      eval `cat $GLOBAL_PATH_TO_TOP/zm-build/$package_list_file`;
      Die("Error in $package_list_file", "$@") if ($@);
   }

   return \@PACKAGES;
}


sub GetNewBuildNo()
{
   my $line = 1000;

   if ( -f "/tmp/build_counter.txt" )
   {
      open( FD1, "<", "/tmp/build_counter.txt" );
      $line = <FD1>;
      close(FD1);

      $line += 2;
   }

   open( FD2, ">", "/tmp/build_counter.txt" );
   printf( FD2 "%s\n", $line );
   close(FD2);

   return $line;
}

sub GetNewBuildTs()
{
   chomp( my $x = `date +'%Y%m%d%H%M%S'` );

   return $x;
}

sub GetBuildOS()
{
   chomp( my $r = `$GLOBAL_PATH_TO_TOP/zm-build/rpmconf/Build/get_plat_tag.sh` );

   return $r
     if ($r);

   Die("Unknown OS");
}

sub GetBuildArch()    # FIXME - use standard mechanism
{
   chomp( my $PROCESSOR_ARCH = `uname -m | grep -o 64` );

   my $b_os = GetBuildOS();

   return "amd" . $PROCESSOR_ARCH
     if ( $b_os =~ /UBUNTU/ );

   return "x86_" . $PROCESSOR_ARCH
     if ( $b_os =~ /RHEL/ || $b_os =~ /CENTOS/ );

   Die("Unknown Arch");
}


##############################################################################################

sub Clone($)
{
   my $repo_details = shift;

   my $repo_name   = $repo_details->{name};
   my $repo_user   = $repo_details->{user};
   my $repo_branch = $repo_details->{branch};

   if ( !-d $repo_name )
   {
      System( "git", "clone", "-b", $repo_branch, "ssh://git\@stash.corp.synacor.com:7999/$repo_user/$repo_name.git" );
   }
   else
   {
      if ( !defined $ENV{ENV_GIT_UPDATE_INCLUDE} || grep { $repo_name =~ /$_/ } split( ",", $ENV{ENV_GIT_UPDATE_INCLUDE} ) )
      {
         print "#: Updating $repo_name...\n";

         chomp( my $z = `cd $repo_name && git pull origin` );

         print $z . "\n";

         if ( $z !~ /Already up-to-date/ )
         {
            System( "find", $repo_name, "-name", ".built.*", "-exec", "rm", "-f", "{}", ";" );
            open( FD, "> $repo_name/.force-clean" );
            close(FD);
         }
      }
   }
}

sub System(@)
{
   my $sep = "";

   print color('bright_green');
   print "#: ";
   for my $a (@_)
   {
      print $sep . $a;
      $sep = " \\\n   ";
   }

   print $sep . " #(pwd=" . Cwd::getcwd() . ")\n\n";
   print color('reset');

   my $x = system @_;

   Die("cmd='@_'", "ret=$x")
      if ( $x != 0 );
}


sub LoadProperties($)
{
   my $f = shift;

   my $x = SlurpFile($f);

   my %h = map { split( /\s*=\s*/, $_, 2 ) } @$x;

   return \%h;
}


sub SlurpFile($)
{
   my $f = shift;

   open( FD, "<", "$f" ) || Die("In open", "file='$f'");

   chomp( my @x = <FD> );
   close(FD);

   return \@x;
}


sub DetectPrerequisite($;$)
{
   my $util_name       = shift;
   my $additional_path = shift || "";

   chomp( my $detected_util = `PATH="$additional_path:\$PATH" \\which "$util_name" 2>/dev/null | sed -e 's,//*,/,g'` );

   return $detected_util
     if ($detected_util);

   Die("Prerequisite '$util_name' missing in PATH");
}


sub Run(%)
{
   my %args  = (@_);
   my $chdir = $args{cd};
   my $call  = $args{call};

   my $child_pid = fork();

   Die("FAILURE while forking")
     if ( !defined $child_pid );

   if ( $child_pid != 0 )    # parent
   {
      while ( waitpid( $child_pid, 0 ) == -1 ) { }
      my $x = $?;

      Die("run $!", $x)
        if ( $x != 0 );
   }
   else
   {
      chdir($chdir)
        if ($chdir);

      my $ret = &$call;
      exit($ret);
   }
}

sub Die($;$)
{
   my $msg = shift;
   my $info = shift || "";
   my $err = "$!";

   use Text::Wrap;

   print "\n";
   print "\n";
   print "=========================================================================================================\n";
   print color('red') . "FAILURE MSG" . color('reset') . " : " . wrap('', '            : ', $msg) . "\n";
   print color('red') . "SYSTEM ERR " . color('reset') . " : " . wrap('', '            : ', $err) . "\n" if($err);
   print color('red') . "EXTRA INFO " . color('reset') . " : " . wrap('', '            : ', $info) . "\n" if($info);
   print "\n";
   print "=========================================================================================================\n";
   print color('red');
   print "--Stack Trace--\n";
   my $i = 1;
   while ( (my @call_details = (caller($i++))) )
   {
      print $call_details[1] . ":" . $call_details[2] . " called from " . $call_details[3] . "\n";
   }
   print color('reset');
   print "\n";
   print "=========================================================================================================\n";

   die "ABORTING";
}