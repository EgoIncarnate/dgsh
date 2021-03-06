#!/bin/sh
#
# Regression tests for dgsh-tee
#

# Ensure that the files passed as 2nd and 3rd arguments are the same
ensure_same()
{
	echo "$1"
	if ! diff $2 $3 >/dev/null
	then
		echo "$1: $2 and $3 differ" 1>&2
		exit 1
	fi
}

# Ensure that the numbers in the files passed as 2nd and 3rd arguments
# about are the same
# Line format:
# Buffers allocated: 1025 Freed: 1024 Maximum allocated: 960
ensure_similar_buffers()
{
	echo "$1"
	for nr in 2 3
	do
		for nf in 3 5 8
		do
			if ! awk "
			function abs(v)
			{
				return (v < 0 ? -v : v)
			}
			NR == $nr {ref = \$$nf}
			NR == $nr + 3 {test = \$$nf}
			END { exit (ref + 0 != 0 && abs((test - ref) / ref * 100) > 10) ? 1 : 0 }" "$2" "$3"
			then
				echo "$1: Line $nr, fields $nf of $2 and $3 differ by more than 10%" 1>&2
				exit 1
			fi
		done
	done
}



for flags in '' -I
do
	# Test two input files
	cat dgsh-tee.c dgsh-tee.c /usr/share/dict/words >expected
	./dgsh-tee $flags -b 64 -i dgsh-tee.c -i dgsh-tee.c -i /usr/share/dict/words >a
	ensure_same "Three input $flags" expected a
	rm expected a

	# Test line scatter reliable algorithm (stdin)
	cat -n /usr/share/dict/words >words
	./dgsh-tee $flags -s -b 1000000 <words -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Line scatter reliable stdin $flags" words words2

	# Test line scatter reliable algorithm (pipe)
	cat -n /usr/share/dict/words |
	./dgsh-tee $flags -s -b 1000000 -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Line scatter reliable pipe $flags" words words2


	# Test line scatter reliable algorithm (file argument)
	cat -n /usr/share/dict/words >words
	./dgsh-tee $flags -s -b 1000000 -i words -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Line scatter reliable file $flags" words words2

	# Test scatter to blocking sinks
	cat -n /usr/share/dict/words >words
	for buffer in 128 1000000
	do
		perl dgsh.pl -o - -p . <<EOF |
		scatter |{ -s -p 8
			-| cat |-
		|} gather |{
			# Merge sorted counts
			sort -mn <-
		|} <words >a
EOF
		sed "s/dgsh-tee  *-s/dgsh-tee -s -b $buffer/" |
		# Logging for the debug version
		# sed 's/-o $SGDIR\/npfo-_unnamed_0.\(.\)/& 2>ilog.\1/' |
		sh
		ensure_same "Scatter to blocking sinks $flags -b $buffer" words a
	done
	rm a

	# Test line scatter efficient algorithm
	./dgsh-tee $flags -s -b 128 <words -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Line scatter efficient $flags" words words2

	# Test with a buffer smaller than line size
	./dgsh-tee $flags -s -b 5 <words -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Small buffer $flags" words words2

	# Test with data less than the buffer size
	head -50 /usr/share/dict/words | cat -n >words
	./dgsh-tee $flags -s -b 1000000 <words -o a -o b -o c -o d
	cat a b c d | sort -n >words2
	ensure_same "Large buffer $flags" words words2
	rm words words2

	# Test block scatter
	./dgsh-tee $flags -s -b 64 <dgsh-tee.c -o a -o b -o c -o d
	./charcount <dgsh-tee.c >orig
	cat a b c d | ./charcount >new
	ensure_same "Block scatter $flags" orig new
	rm a b c d orig new

	# Test plain distribution
	./dgsh-tee $flags -b 64 <dgsh-tee.c -o a -o b
	ensure_same "Plain distribution $flags" dgsh-tee.c a
	ensure_same "Plain distribution $flags" dgsh-tee.c b
	rm a b

	# Test output to stdout
	./dgsh-tee $flags -b 64 <dgsh-tee.c >a
	ensure_same "Stdout $flags" dgsh-tee.c a
	rm a

	# Test buffering
	# When -l is supported add, say, -l 16
	for flags2 in '' '-m 2k' '-m 2k -f'
	do
		test="tee-fastout$flags$flags2"
		dd bs=1k count=1024 if=/dev/zero 2>/dev/null | ./dgsh-tee -M $flags $flags2 -b 1024 >/dev/null 2>"test/tee/$test.test"
		ensure_similar_buffers "$test" "test/tee/$test.ok" "test/tee/$test.test"
		test="tee-lagout$flags$flags2"
		dd bs=1k count=1024 if=/dev/zero 2>/dev/null | ./dgsh-tee -M $flags $flags2 -b 1024 2>"test/tee/$test.test" | (sleep 1 ; cat >/dev/null)
		ensure_similar_buffers "$test" "test/tee/$test.ok" "test/tee/$test.test"
	done

	# Test low-memory behavior (memory)
	rm -f try try2
	mkfifo try try2
	perl -e 'for ($i = 0; $i < 500; $i++) { print "x" x 500, "\n"}' | tee lines | ./dgsh-tee $flags -b 512 -m 2k -o try -o try2 2>err &
	cat try2 >try2.out &
	{ read x ; echo $x ; sleep 1 ; cat ; } < try > try.out &
	wait
	if [ "$flags" = '-I' ]
	then
		ensure_same "Low-memory $flags error" err test/tee/oom.err
	else
		ensure_same "Low-memory (try) $flags" lines try.out
		ensure_same "Low-memory (try2) $flags" lines try2.out
	fi
	rm -f lines try try2 try.out try2.out err

	# Test low-memory behavior (file)
	rm -f try try2
	mkfifo try try2
	perl -e 'for ($i = 0; $i < 500; $i++) { print "x" x 500, "\n"}' | tee lines | ./dgsh-tee -f $flags -b 512 -m 2k -o try -o try2 2>err &
	cat try2 >try2.out &
	{ read x ; echo $x ; sleep 1 ; cat ; } < try > try.out &
	wait
	ensure_same "Low-memory temporary file (try) $flags" lines try.out
	ensure_same "Low-memory temporary file (try2) $flags" lines try2.out
	rm -f lines try try2 try.out try2.out err
done

# Test asynchronous reading from multiple input files
# Without it the following blocks
# Also test multiple temporary files
for flags in '' '-m 65536 -f'
do
	rm -f a b c d
	mkfifo a b c
	./dgsh-tee -b 4096 -m 65536 -i /usr/share/dict/words -o a -o b -o c &
	./dgsh-tee -b 4096 -I $flags -i a -i b -i c -o d &
	wait
        for i in . . .
        do
                cat /usr/share/dict/words
        done >expect
	ensure_same "Asynchronous gather $flags" expect d
	rm -f a b c d expect
done

exit 0
