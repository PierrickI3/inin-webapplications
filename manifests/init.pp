include pget
include unzip

# == Class: cicwebapplications::install
#
# Installs CIC Web applications and configures them.
# CIC Web Applications Zip files (i.e. CIC_Web_Applications_2015_R3.iso) should be in a shared folder 
# linked to C:\daas-cache
#
# === Parameters
#
# [ensure]
#   installed. No other values are currently supported.
#
#
# === Examples
#
#  class {'cicwebapplications=::install':
#   ensure                  => installed,
#  }
#
# === Authors
#
# Pierrick Lozach <pierrick.lozach@inin.com>
#
# === Copyright
#
# Copyright 2015, Interactive Intelligence Inc.
#

class cicwebapplications::install (
  $ensure = installed,
)
{

  $daascache                        = 'C:/daas-cache/'
  $currentversion                   = '2015_R3'
  $latestpatch                      = 'Patch8'

  $webapplicationszip               = "CIC_Web_Applications_${currentversion}.zip"
  $webapplicationslatestpatchzip    = "CIC_Web_Applications_${currentversion}_${latestpatch}.zip"
  
  $server                           = $::hostname
  
  if ($::operatingsystem != 'Windows')
  {
    err('This module works on Windows only!')
    fail('Unsupported OS')
  }

  $cache_dir = hiera('core::cache_dir', 'c:/users/vagrant/appdata/local/temp') # If I use c:/windows/temp then a circular dependency occurs when used with SQL
  if (!defined(File[$cache_dir]))
  {
    file {$cache_dir:
      ensure   => directory,
      provider => windows,
    }
  }

  case $ensure
  {
    installed:
    {
      # Create folder in wwwroot
      file { 'C:/inetpub/wwwroot/ININApps':
        ensure => directory,
      }

      # Unzip web applications zip file
      unzip {'Unzip Web Applications':
        name        => "${daascache}${webapplicationszip}",
        destination => "${cache_dir}/ININApps",
        creates     => "${cache_dir}/ININApps/install.txt",
        require     => File['C:/inetpub/wwwroot/ININApps'],
      }

      # Copy the web_files folder to inetpub\wwwroot
      exec {'Copy web_files':
        command  => 'Copy-Item C:\\Users\\vagrant\\AppData\\Local\\Temp\\ININApps\\web_files\\* C:\\inetpub\\wwwroot\\ININApps\\ -Recurse -Force',
        provider => powershell,
        require  => Unzip['Unzip Web Applications'],
      }

      # Download Microsoft Application Request Routing Version 3 for IIS
      pget {'Download Microsoft Application Request Routing V3':
        source => 'http://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi',
        target => $cache_dir,
      }

      # Install the Microsoft Application Request Routing Version 3 for IIS
      package {'Microsoft Application Request Routing V3':
        ensure          => installed,
        source          => "${cache_dir}/requestRouter_x64.msi",
        install_options => [
          '/l*v',
          'c:\\windows\\logs\\requestRouter_x64.log',
        ],
        provider        => 'windows',
        require         => Pget['Microsoft Application Request Routing V3'],
      }

      # Enable Proxy
      exec {'Enable proxy settings':
        command  => 'Set-WebConfigurationProperty -pspath \'IIS:\' -filter "system.webServer/proxy" -name "enabled" -value "True"',
        provider => powershell,
        require  => Package['Microsoft Application Request Routing V3'],
      }

      # Remove Default Web Site
      iis_site {'Default Web Site':
        ensure => absent,
      }

      # Create application pool (disable .Net runtime)
      iis_apppool {'ININApps':
        ensure                => present,
        managedruntimeversion => '',
      }

      # Create a new site called ININApps
      iis_site {'ININApps':
        ensure   => present,
        bindings => ['http/*:80:'],
        require  => [
          Iis_Site['Default Web Site'],
          Iis_Apppool['ININApps'],
          Exec['Enable proxy settings'],
        ],
      }

      # Create virtual application
      iis_app {'ININApps/':
        ensure          => present,
        applicationpool => 'ININApps',
        require         => Iis_Site['ININApps'],
      }

      # Create virtual directory
      iis_vdir {'ININApps/':
        ensure       => present,
        iis_app      => 'ININApps/',
        physicalpath => 'C:\\inetpub\\wwwroot\\ININApps',
        require      => Iis_App['ININApps/'],
      }

      # Update the maximum URL size in Request Filtering
      exec{'set-max-url-size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxurl:8192\"",
        path    => $::path,
        cwd     => $::system32,
        require => Iis_Vdir['ININApps/'],
      }

      # Update the maximum query string size in Request Filtering
      exec{'set-max-query-string-size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxquerystring:8192\"",
        path    => $::path,
        cwd     => $::system32,
        require => Iis_Vdir['ININApps/'],
      }
      
      # Download URL Rewrite module
      pget {'Download URL Rewrite module':
        source => 'http://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi',
        target => $cache_dir,
      }

      # Install URL Rewrite module
      package {'Install URL Rewrite module':
        ensure          => installed,
        source          => "${cache_dir}/rewrite_amd64.msi",
        install_options => [
          '/l*v',
          'c:\\windows\\logs\\rewrite_amd64.log',
        ],
        provider        => 'windows',
        require         => Pget['Download URL Rewrite module'],
      }

      # Add WEB_APP allowed server variable
      exec{'Add WEB_APP allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'WEB_APP\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="WEB_APP"]\' | Select name | Select-String WEB_APP) { Exit 1 }',
      }

      # Add ICWS_HOST allowed server variable
      exec{'Add ICWS_HOST allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'ICWS_HOST\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="ICWS_HOST"]\' | Select name | Select-String ICWS_HOST) { Exit 1 }',
      }

      # Add HTTP_ININ-ICWS-Original-URL allowed server variable
      exec{'Add HTTP_ININ-ICWS-Original-URL allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'HTTP_ININ-ICWS-Original-URL\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="HTTP_ININ-ICWS-Original-URL"]\' | Select name | Select-String HTTP_ININ-ICWS-Original-URL) { Exit 1 }',
      }

      # Add MapScheme rewrite map
      exec {'Add MapScheme rewrite map':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/rewriteMaps" -name "." -value @{name=\'MapScheme\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' | Select name | Select-String MapScheme) { Exit 1 }',
        require  => [
          Exec['Add WEB_APP allowed server variables'],
          Exec['Add ICWS_HOST allowed server variables'],
          Exec['Add HTTP_ININ-ICWS-Original-URL allowed server variables'],
        ],
      }

      # Add https map entry
      exec {'Add https map entry':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\'  -filter "system.webServer/rewrite/rewriteMaps/rewriteMap[@name=\'MapScheme\']" -name "." -value @{key=\'on\';value=\'https\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' -name Collection  | Select-Object value | Select-String -pattern "https\b") { Exit 1 }',
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Add http map entry (onlyif needs to be improved as it also matches 'https')
      exec {'Add http map entry':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\'  -filter "system.webServer/rewrite/rewriteMaps/rewriteMap[@name=\'MapScheme\']" -name "." -value @{key=\'off\';value=\'http\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' -name Collection  | Select-Object value | Select-String -pattern "http\b") { Exit 1 }',
        require  => Exec['Add MapScheme rewrite map'],
      }

      exec {'Add inbound rule':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/globalRules" -name "." -value @{name=\'inin-api-rewrite\';patternSyntax=\'Regular Expressions\';stopProcessing=\'True\'}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/globalRules/rule[@name=\'inin-api-rewrite\']" -Name "." | Select-Object name | Select-String inin-api-rewrite) { Exit 1 }',
        provider => powershell,
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Set inbound rule type to Rewrite
      exec {'Set inbound rule type':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/action\' -name \'type\' -value \'Rewrite\'',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

    }
    default:
    {
      fail("Unsupported ensure \"${ensure}\"")
    }
  }
}