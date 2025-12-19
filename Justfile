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
    if (which gh | length) == 0 {
      print "Error: You need the github cli installed to run this update"
      exit 1
    }
    let path = '{{path}}'
    let repo = '{{repo}}'
    let latestTag = gh api $"repos/($repo)/releases/latest" --cache 1h
      | from json
      | get tag_name
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
    if (which gh | length) == 0 {
      print "Error: You need the github cli installed to run this update"
      exit 1
    }
    let mPath = '{{path}}'
    let path = if ($mPath == "optional") {
      open .subtree.toml | columns | str join "\n" | fzf
    } else {
      $mPath
    }
    let subtree = open .subtree.toml | get $path
    let latestTag = gh api $"repos/($subtree.src)/releases/latest" --cache 1h
      | from json
      | get tag_name
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
    
[group('subtree')]
arborium-update:
    #!/usr/bin/env -S nu -n
    if (which gh | length) == 0 {
      print "Error: You need the github cli installed to run this update"
      exit 1
    }
    let subtree = open "vendor/bearcove/arborium/ref.toml"
    let path = "vendor/bearcove/arborium/langs"
    let latestTag = gh api repos/bearcove/arborium/tags --cache 1h
      | from json
      | each { get name }
      | sort-by { parse 'v{maj}.{min}.{patch}' | get 0
                   | (((($in.maj | into int) * 10_000) + ($in.min | into int)) * 10_000) + ($in.patch | into int) }
      | last
    if $latestTag == $subtree.tag {
      print $"Already up to date; release is ($latestTag)"
    } else {
      print $"Updating ($path) from ($subtree.src)/($subtree.tag) to ($latestTag)..."
      try {
        git remote remove bearcovearb
      } 
      git remote add --no-tags --no-fetch bearcovearb $"https://github.com/($subtree.src).git" 
      try {
        git fetch bearcovearb $latestTag
        git merge -s ours --no-commit --allow-unrelated-histories --squash $latestTag
        git rm -rf $path
        git read-tree --prefix=vendor/bearcove/arborium/langs -u $"($latestTag):langs"
        $subtree
            | upsert tag $latestTag
            | to toml
            | save -f vendor/bearcove/arborium/ref.toml
        git add vendor/bearcove/arborium/ref.toml
        git commit --message $"update: ($subtree.src) ($subtree.tag) -> ($latestTag)\n\nUpdating ($path) with the latest changes from ($subtree.src)@($latestTag)"
      }
    }
    


  
