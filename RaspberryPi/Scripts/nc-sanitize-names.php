#!/usr/bin/env php
<?php
// Apply each user's .rename.user.conf to files already on disk.
// Dry run by default; pass --apply to actually rename.
//   sudo -u www-data php nc-sanitize-names.php admin jesper > map.tsv
declare(strict_types=1);

require '/var/www/nextcloud/apps/files_autorename/lib/Service/RuleAnnotation.php';
require '/var/www/nextcloud/apps/files_autorename/lib/Service/RenameRuleParser.php';

use OCA\Files_AutoRename\Service\RenameRuleParser;

const DATA_DIR = '/mnt/nextcloud-ssd';
const SKIP = ['.rename.conf', '.rename.user.conf', '.rename.groupfolder.conf'];

// Mirrors RenameFileProcessor::matchRules() + applyTransformations().
function sanitize(array $rules, string $rel): string {
  foreach ($rules as $rule) {
    if (preg_match($rule['patterns'][0], $rel)) {
      $rel = preg_replace($rule['patterns'], $rule['replacements'], $rel);
      break; // only the first matching rule applies
    }
  }
  return preg_replace_callback(
    '/(upper|lower)\((.*?)\)/',
    fn($m) => $m[1] === 'upper' ? strtoupper($m[2]) : strtolower($m[2]),
    $rel
  );
}

$args = array_slice($argv, 1);
$apply = in_array('--apply', $args, true);
$users = array_values(array_filter($args, fn($a) => $a !== '--apply'));

if (!$users) {
  fwrite(STDERR, "usage: nc-sanitize-names.php [--apply] <user>...\n");
  exit(2);
}

$renamed = $collisions = 0;

foreach ($users as $user) {
  $root = DATA_DIR . "/$user/files";
  $conf = "$root/.rename.user.conf";
  if (!is_file($conf)) {
    fwrite(STDERR, "skip $user: no .rename.user.conf\n");
    continue;
  }
  $rules = (new RenameRuleParser())->parse(file_get_contents($conf));

  // Collect first, rename after - renaming mid-iteration can skip entries.
  $files = [];
  $it = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
  );
  foreach ($it as $f) {
    if ($f->isFile() && !in_array($f->getFilename(), SKIP, true)) {
      $files[] = $f->getPathname();
    }
  }

  foreach ($files as $path) {
    $rel = substr($path, strlen($root) + 1);
    $new = sanitize($rules, $rel);
    if ($new === $rel) {
      continue;
    }
    $dst = "$root/$new";
    if (file_exists($dst)) {          // matches the app's ConflictCancel default
      fwrite(STDERR, "COLLISION\t$user\t$rel\t$new\n");
      $collisions++;
      continue;
    }
    echo "$user\t$rel\t$new\n";
    $renamed++;
    if ($apply && !rename($path, $dst)) {
      fwrite(STDERR, "FAILED\t$user\t$rel\n");
    }
  }
}

fwrite(STDERR, sprintf("%s: %d renames, %d collisions\n",
  $apply ? 'applied' : 'dry run', $renamed, $collisions));
