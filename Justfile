[group('subtree')]
subtree-list:
    #!/usr/bin/env nu
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
    



  
