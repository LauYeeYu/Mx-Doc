#!/bin/bash

# Usage: scripts/test.bash <compiler> <testcase> <builtin> [tempdir]
# Example:
#     scripts/test.bash 'bin/mxc -emit-llvm' testcases/codegen/t1.mx bin/builtin.ll
# The script will
# 1. Get an temporary directory
# 2. Execute <compiler> < <testcase> > "$TEMPDIR/output.ll"
# 3. Get the test.in and test.ans from <testcase> using sed
# 4. Execute clang "$TEMPDIR/output.ll" "$3" -m32 -o "$TEMPDIR/exe"
# 5. Execute "$TEMPDIR/exe" < "$TEMPDIR/test.in" > "$TEMPDIR/test.out"

# Usage
if [ $# -ne 3 ] && [ $# -ne 4 ]; then
    cat << EOF >&2 
Usage: $0 <complier> <testcase> <builtin> [tempdir]
       If you need to pass arguments to the compiler, please use
       quotation mark(') to pack the arguments along with the compiler
       command. For example,
       $0 'bin/mxc -a -b -c' testcases/codegen/t1.mx bin/builtin.ll
EOF
    exit 1
fi


if [ ! -f $2 ]; then
    echo "Error: testcase file $2 does not exist." >&2
    exit 1
fi
if [ ! -f $3 ]; then
    echo "Error: builtin file $3 does not exist." >&2
    exit 1
fi
source $(dirname $0)/utils.bash

# Get the clang
which clang-15 > /dev/null 2> /dev/null
if [ $? -eq 0 ]; then
    CLANG=clang-15
else
    which clang-16 > /dev/null 2> /dev/null
    if [ $? -eq 0 ]; then
        CLANG=clang-16
    else
        which clang-17 > /dev/null 2> /dev/null
        if [ $? -eq 0 ]; then
            CLANG=clang-17
        else
            test_bin clang
            CLANG=clang
            exit 1
        fi
    fi
fi

# 1. Make temp directory
if [ $# -eq 4 ]; then
    TEMPDIR=$4
    USER_DEFINED_TEMPDIR=1
else
    TEMPDIR="$(mktemp -d -p /tmp mxc.XXXXXXXXXX)"
    USER_DEFINED_TEMPDIR=0
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create temp directory." >&2
        exit 1
    fi
fi

clean() {
    if [ $USER_DEFINED_TEMPDIR -eq 0 ]; then
        rm -rf "$TEMPDIR"
    fi
}

print_temp_dir() {
    cat <<EOF >&2
All generated files are at '$TEMPDIR'. You may check some files there.
For example, you may check the output of your compiler at '$TEMPDIR/output.ll'.
Use the following command to clean up the temp directory:
    rm -rf "$TEMPDIR"
EOF
}

# 2. Compile the testcase
$1 < $2 > "$TEMPDIR/output.ll" 2> /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Failed to compile $2." >&2
    clean
    exit 1
fi

# 3. Get the test.in and test.ans from <testcase> using sed
sed -n '/=== input ===/,/=== end ===/{//!p}' $2 > "$TEMPDIR/test.in"
if [ $? -ne 0 ]; then
    echo "Error: Failed to get input from $2." >&2
    clean
    exit 1
fi
sed -n '/=== output ===/,/=== end ===/{//!p}' $2 > "$TEMPDIR/test.ans"
if [ $? -ne 0 ]; then
    echo "Error: Failed to get output from $2." >&2
    clean
    exit 1
fi
EXPECTED_EXIT_CODE=$(grep "ExitCode:" $2 | awk '{print $2}')

# 4. Execute the code with clang
$CLANG "$TEMPDIR/output.ll" "$3" -m32 -o "$TEMPDIR/exe" > /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Failed to compile '$TEMPDIR/output.ll'." >&2
    print_temp_dir
    exit 1
fi

# 5. Execute the code
"$TEMPDIR/exe" < "$TEMPDIR/test.in" > "$TEMPDIR/test.out" 2> /dev/null
EXIT_CODE=$?
HAS_PROBLEM=0
diff -ZB "$TEMPDIR/test.out" "$TEMPDIR/test.ans" >&2
if [ $? -ne 0 ]; then
    echo "Error: Output mismatch." >&2
    print_temp_dir
    HAS_PROBLEM=1
fi
if [ $EXIT_CODE -ne $EXPECTED_EXIT_CODE ]; then
    echo "Error: Exit code mismatch." >&2
    print_temp_dir
    HAS_PROBLEM=1
fi

if [ $HAS_PROBLEM -eq 0 ]; then
    print_green_msg "Passed"
    clean
    exit 0
else
    print_red_msg "Failed"
    print_temp_dir
    exit 1
fi
