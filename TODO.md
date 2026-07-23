[nextcloud notes](https://ven0m0.dpdns.org/nextcloud/apps/notes/welcome) has the following error: "Creating new note has failed. HTTP 500 (OCP\Files\NotPermittedException)"

also fix:
"
WebDAV endpoint
Your web server is not yet properly set up to allow file synchronization, because the WebDAV interface seems to be broken. To allow this check to run you have to make sure that your Web server can connect to itself. Therefore it must be able to resolve and connect to at least one of its `trusted_domains` or the `overwrite.cli.url`. This failure may be the result of a server-side DNS mismatch or outbound firewall rule.
Mimetype migrations available
One or more mimetype migrations are available. Occasionally new mimetypes are added to better handle certain file types. Migrating the mimetypes take a long time on larger instances so this is not done automatically during upgrades. Use the command `occ maintenance:repair --include-expensive` to perform the migrations.
HTTP headers
Some headers are not set correctly on your instance - The `Strict-Transport-Security` HTTP header is not set (should be at least `15552000` seconds). For enhanced security, it is recommended to enable HSTS.
Database missing indices
Detected some missing optional indices. Occasionally new indices are added (by Nextcloud or installed applications) to improve database performance. Adding indices can sometimes take awhile and temporarily hurt performance so this is not done automatically during upgrades. Once the indices are added, queries to those tables should be faster. Use the command `occ db:add-missing-indices` to add them. Missing indices: "rd_wopi_expiry_idx" in table "richdocuments_wopi"
PHP opcache
The PHP OPcache module is not properly configured. The OPcache interned strings buffer is nearly full. To assure that repeating strings can be effectively cached, it is recommended to apply "opcache.interned_strings_buffer" to your PHP configuration with a value higher than "8"..
"

- set the Default phone region to germany

work on:
"
Configuration server ID
Server identifier isn’t configured. It is recommended if your Nextcloud instance is running on several PHP servers. Add a server ID in your configuration.
PHP modules
This instance is missing some recommended PHP modules. For improved performance and better compatibility it is highly recommended to install them: - gmp required for SFTP storage and recommended for WebAuthn performance
PHP Imagick module
The PHP module "imagick" is not enabled although the theming app is. For favicon generation to work correctly, you need to install and enable this module.
"
