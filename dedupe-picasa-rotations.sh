#!/bin/bash
set -e

DIR="$1"
TRASH="$DIR/trash"
mkdir -p "$TRASH"

# from http://www.imagemagick.org/Usage/compare/
images_equiv() {
  local options="-compose Difference -composite -colorspace gray -verbose info:"
  if convert "$1" "$2" $options |
     sed -n '/statistics:/,/^  [^ ]/p' |
     grep -q '^      .*: .*[1-9].*$' # Any non-zero value means not equal.
  then
    return 1 # not equal
  else
    return 0 # yes, files are equal
  fi
}

fix_equiv() {
  local r="$1" # the image just rotated
  local f="$2" # the image modified by picasa
  local o="$3" # the original image
  [ "$r" = "$f" ] && exit 1
  if images_equiv "$r" "$f"; then
    echo "  Match!  Keeping the image rotated by $tool."
    # Note: this function may be called if samesize, in which case there was
    # no rotation done, so $r = $o.  In that case, don't delete the original
    # before trying to move the "rotation" into place!
    if [ "$o" != "$r" ]; then
      mv "$o" "$TRASH/orig-$b"
    fi
    mv "$f" "$TRASH/picasa-$b"
    mv "$r" "$f"
  else
    # TODO: if no orientation info was available, this may result in
    # upside-down pictures. (Or if photo had already been rotated without
    # removing the orientation EXIF field, then you get 270-rot originals).
    if [ "$o" != "$r" ]; then
      echo "  Files do not match.  Rotating the original."
      mv "$o" "$TRASH/orig-$b"
      mv "$r" "$o"
    else
      echo "  Files do not match.  Doing nothing."
    fi
  fi
}

find "$DIR" -type f -name "*.jpg" -o -name "*.JPG" |
grep -v picasaoriginals |
while read f; do
  d=`dirname "$f"`
  b=`basename "$f"`
  o="$d/.picasaoriginals/$b"
  r="$d/.picasaoriginals/tmp-rotated-$b"
  if [ -f "$o" ]; then
    fres=`jhead "$f" | sed -n 's/^Resolution *: *//p'`
    ores=`jhead "$o" | sed -n 's/^Resolution *: *//p'`
    fswp=`echo "$fres" | sed 's/\([0-9]*\) x \([0-9]*\)/\2 x \1/'`
    if [ "$ores" = "$fswp" ]; then
      echo "rotated : $f"
      if jhead "$o" | grep -q "^Orientation"; then
        # jhead -autorot uses jpegtran, but also adjusts the resolution and
        # orientation fields in the EXIF data, so the images should appear
        # correctly in any editor.  Hence, better than just using jpegtran,
        # so use if possible.
        cp "$o" "$r" && jhead -autorot "$r"
        tool="jhead"
      else
        # Take a guess at 90-degrees... could be 270, but most are 90.
        jpegtran -rotate 90 -copy all "$o" > "$r"
        jhead -norot "$r" # Remove the Orientation EXIF field
        tool="jpegtran"
      fi
      fix_equiv "$r" "$f" "$o"
    elif [ "$ores" = "$fres" ]; then
      if cmp -s "$o" "$f"; then
        echo "samefile: $f"
        mv "$o" "$TRASH/orig-$b"
      else
        echo "samesize: $f"
        tool="(no rotation done)"
        fix_equiv "$o" "$f" "$o"
      fi
    else
      echo "diffsize: $f"
    fi
  fi
done

