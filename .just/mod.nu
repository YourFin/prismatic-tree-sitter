# gh repo: owner/repo 
export def latest-tag [repo: string] {
   if (which gh | length) == 0 {
     print "Error: You need the github cli installed to run this update"
     exit 1
   }
   try {
     (gh api $"repos/($repo)/releases/latest" --cache 1h
          e> /dev/null
          | from json
          | get tag_name)
   } catch { 
     gh api $"repos/($repo)/tags" --cache 1h
        | from json
        | each { get name }
        | sort-by { parse 'v{maj}.{min}.{patch}' | get 0
                    | (((($in.maj | into int) * 10_000) + ($in.min | into int)) * 10_000) + ($in.patch | into int) }
        | last
   }
}
