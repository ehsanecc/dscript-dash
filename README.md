# dscript-dash  
Script to **capture**, **analyse** and **download** custom contents(files) from various websites (based on most common unix tools like wget, curl, and so on)  
```
Usage:  
    -- help              this message will pop up  
    -u <topic-url-with-%n%>  
    --remove-duplicates  remove duplicates from current folder  
    --remove-corrupts    remove corrupted files(jpg)  
    --rename             rename all files(in case of all captured files have same name)  
    --filter <str>       only links with str in them will process  
    --smart-download     this enable smart download feature, which only a download  
                         new files(based on sizes and (if equal) partial md5sum's)  
    --threads <int>      number of threads used for downloading, don't confuse with partial  
    			               downloading, it's multi-thread downloading single files.(default=1)  
    --capture-all        first capture all pages links, then proceed with links.  
                         usefull when content is update quickly  
    --capture-only       only capture and save the links to captured_links file  
    --cookie <str>       set cookie, style: PHPID=blablabla!  
    --order <start=0>:<step=1>:<end>  
    --tag                html tag to proceed (default="img:src")  
    --follow             follow internal links(depth=1), and then search for tags  
    -t <translate>       translate site links to desired links.  
                       for example change _small tag to _large tag and so on.  
  
example1: This command will download every image in page=0, page=1, page=2, ... until the end or duplicate pages found:  
  dscript.sh "http://www.foo.com/bar.php?page=%n%"  
example2: This command tries to find and remove duplicate files based on size & content of downloaded files  
  dscript.sh --remove-duplicates ; will remove duplicate files in current folder  
example3: This is same as example1, but change the _large tag to _small used *sed* utility and set cookie for webpage  
  dscript.sh "http://www.foo.com/bar.php?page=%n%" -t "sed s/_large/_small/g" --cookie "COOKIE1=10000001"  
```
