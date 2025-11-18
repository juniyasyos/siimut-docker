<?php
/**
 * phpMyAdmin configuration file
 */

// Set PHP configuration
ini_set('upload_max_filesize', '1024M');
ini_set('post_max_size', '1024M');
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 600);
ini_set('max_input_time', 600);
ini_set('max_input_vars', 10000);
ini_set('output_buffering', 4096);

/**
 * Server configuration
 */
$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'db';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;

/**
 * Configuration storage settings
 */
$cfg['blowfish_secret'] = 'a8b7c6d5e4f3g2h1i0j9k8l7m6n5o4p3q2r1s0t9u8v7w6x5y4z3';

/**
 * Upload/import settings
 */
$cfg['UploadDir'] = '/var/lib/phpmyadmin/upload';
$cfg['SaveDir'] = '/var/lib/phpmyadmin/save';
$cfg['MaxSizeForInputField'] = 1024 * 1024 * 1024; // 1GB

/**
 * Directories for saving/loading files from server
 */
$cfg['TempDir'] = '/tmp/';

/**
 * Session configuration
 */
$cfg['SessionSavePath'] = '/sessions';

/**
 * Other settings
 */
$cfg['CheckConfigurationPermissions'] = false;
$cfg['DefaultLang'] = 'en';
$cfg['DefaultConnectionCollation'] = 'utf8mb4_unicode_ci';
$cfg['ZipDump'] = true;
$cfg['GZipDump'] = true;
$cfg['BZipDump'] = true;

/**
 * Prevent timeout issues
 */
$cfg['ExecTimeLimit'] = 600;
$cfg['MemoryLimit'] = '1024M';