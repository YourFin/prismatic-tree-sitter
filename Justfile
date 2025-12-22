cabal-build: hpack
    cabal build all

gen-cabal-project:
    #!/usr/bin/env -S nu -n
    glob lang/*/*.cabal
      | each { path dirname | path relative-to ('.' | path expand) }
      | prepend "prismatic-tree-sitter-core"
      | each { $"  ($in)" }
      | prepend [ "packages:" ]
      | str join "\n"
      | save -f cabal.project

hpack: gen-cabal-project
    #!/usr/bin/env -S nu -n
    let cwd = "." | path expand
    let dirs = (open cabal.project
      | lines
      | skip 1
      | take until { $in =~ "^\\s+$" }
      | each { str trim }
      | each { glob $in }
      | flatten
      | each { |f|
          if ($f | path type) == "file" {
            $f | path dirname
          } else {
            $f
          }
        }
      | where (($"($it)/package.yaml" | path type) == file))
    for dir in $dirs {
      cd $dir
      print $"hpack in /($dir | path relative-to $cwd):"
      hpack
      print ""
    }

[group('subtree')]
subtree-list:
    #!/usr/bin/env -S nu -n
    open .subtree.toml | transpose path details


[group('subtree')]
subtree-add path repo:
    #!/usr/bin/env -S nu -n
    use {{justfile_directory()}}/.just *
    let path = '{{path}}'
    let repo = '{{repo}}'
    let latestTag = latest-tag $repo;
    print $"Latest release for ($repo) is ($latestTag); pulling..."
    git subtree add --prefix $path $"https://github.com/($repo).git" $latestTag --squash
    open .subtree.toml
      | insert $path { src: $repo, tag: $latestTag }
      | to toml
      | save -f .subtree.toml
    git add .subtree.toml
    git commit --amend --no-edit
    
[group('subtree')]
subtree-update path="optional":
    #!/usr/bin/env -S nu -n
    let mPath = '{{path}}'
    let path = if ($mPath == "optional") {
      open .subtree.toml | columns | str join "\n" | fzf
    } else {
      $mPath
    }
    let subtree = open .subtree.toml | get $path
    let latestTag = latest-tag $repo
    if $latestTag == $subtree.tag {
      print $"Already up to date; release is ($latestTag)"
    } else {
      print $"Updating ($path) from ($subtree.src)/($subtree.tag) to ($latestTag)..."
      (git subtree pull
        --prefix $path
         --squash
         --message $"update: ($subtree.src) ($subtree.tag) -> ($latestTag)\n\nUpdating ($path) with the latest changes from ($subtree.src)@($latestTag)"
        $"https://github.com/($subtree.src).git" $latestTag )
      open .subtree.toml
        | upsert $path { src: $subtree.src, tag: $latestTag }
        | to toml
        | save -f .subtree.toml
         
      git add .subtree.toml
      git commit --amend --no-edit
    }
