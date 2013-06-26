<?php
$taggutai_real = "C:/taggutai";
$taggutai_web = "http://taggutai"; // use virtual host or something
?>
<?php
if (isset($_GET['ajax']) && isset($_GET['file']))
{
    header('HTTP/200 OK');
    header('Content-Type: text/plain;');

    $array = file("$taggutai_real/meta/".$_GET['file'].'/names');
    echo basename(substr($array[0], strrpos($array[0], '.') + 1, -2));

    ob_end_flush();
    exit();
}
?>
<!DOCTYPE html>
<html><head><title>Storage</title><style type="text/css">
/*.wrapper { margin-left: auto; margin-right: auto; width: 24em; }*/
input { width: 50%; }
html { font-family: monospace; }
</style><script type="text/javascript">
function gettype(fileid)
{
    var xhr = new XMLHttpRequest();

    xhr.open("GET", "<?php echo $taggutai_web;?>/?ajax=gettype&file=" + fileid, false);
    xhr.send();

    var elements = document.getElementsByName('type-' + fileid);

    for (var i = 0; i < elements.length; i++)
    {
        elements[i].innerHTML = xhr.responseText;
    }
}
</script></head><body><div class="wrapper"><ul>
<?php
if (isset($_GET['tag']) && isset($_GET['file']))
{
    $tags = explode('|', $_GET['tag']);
    $file = $_GET['file'];
    $oldtags = file("$taggutai_real/meta/$file/tags");

    unlink("$taggutai_real/meta/$file/tags");

    foreach ($oldtags as $tag)
    {
        $tag = trim($tag);

        unlink("$taggutai_real/tags/$tag/$file");

        if (sizeof(scandir("$taggutai_real/tags/$tag/")) == 2)
        {
            rmdir("$taggutai_real/tags/$tag/");
        }
    }

    foreach ($tags as $tag)
    {
        file_put_contents("$taggutai_real/meta/$file/tags" , "$tag\n", FILE_APPEND);

        if (!file_exists("$taggutai_real/tags/$tag/"))
        {
            mkdir("$taggutai_real/tags/$tag/", 0777, true);
        }

        touch("$taggutai_real/tags/$tag/$file");
    }

    echo "<a href=\"$taggutai_web/\">Success.</a>";
}
elseif (isset($_GET['file']))
{
    $file = $_GET['file'];
    $array = file('$taggutai_real/meta/'.$file.'/names');
    $tags = implode(file("$taggutai_real/meta/$file/tags"), '|');

    switch (basename(trim(substr($array[0], strrpos($array[0], '.') + 1))))
    {
        case "jpg":
        case "jpeg":
        case "png":
        case "gif":
            echo "<img name=\"file\" src=\"$taggutai_web/storage/$file\" />";
            break;
        default:
            echo $file;
    }

    echo "<form action=\"$taggutai_web/?file=$file\" method=\"get\"><input type=\"hidden\" name=\"file\" value=\"$file\" /><input type=\"text\" name=\"tag\" value=\"$tags\" /><input type=\"submit\" /></form>";
}
else
{
    function scan($root)
    {
        if ($handle = opendir($root)) {

            /* This is the correct way to loop over the directory. */
            while (false !== ($entry = readdir($handle))) {
                if ($entry == '.' || $entry == '..')
                {
                    continue;
                }

                if (is_dir($root.$entry))
                {
                    echo "<li>$entry</li><ul>";

                    scan($root.$entry.'/');

                    echo "</ul>";
                }
                else
                {
                    echo "<li><a href=\"http://taggutai/?file=$entry\" onmouseover=\"javascript:gettype('$entry')\">$entry</a><span name=\"type-$entry\"></span></li>";
                }
            }

            closedir($handle);
        }
    }

    scan("$taggutai_real/tags/");
}
?>
</ul></div></body></html>