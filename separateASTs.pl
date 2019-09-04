#
# Copyright 2018 Vinícius Jorge Vendramini
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Call as `perl separateASTs.pl myAST.swiftASTDump`.
# Creates many myAST1.swiftASTDump, myAST2.swiftASTDump, etc. files

$astDumpExtension = "swiftASTDump";

foreach (@ARGV) {
    print "Processing $_...\n";

    $astDumpFilePath = $_;

    # Grab the filename without the extension
    if ($astDumpFilePath =~ /(.*)\.swiftASTDump/) {
        print "Got filename\n";

        $pathWithoutExtension = $1;

        # Open the AST file
        open(my $astDumpFileHandle, "$astDumpFilePath") or die "Could not read from AST file '$astDumpFilePath' $!";

        # Tell perl to read it as binary
        binmode($astDumpFileHandle);
        # And tell it not to stop reading at a newline
        undef $/;
        # Read the file into memory
        my $astDump = <$astDumpFileHandle>;

        # Start a counter for the output file names
        $i = 0;

        # OK to start
        print "Separating $astDumpFilePath\n";
        while ($astDump =~ s/(\(source_file[\s\S]+?)(!?\(source_file)/(source_file/) {

            # Increase the filename counter
            $i = $i + 1;

            # Form the output file name
            $partFileName = "$pathWithoutExtension-$i.$astDumpExtension";

            print "Processing $partFileName...\n";
            # Open or create the output file
            open(my $fileHandle, '>', "$partFileName") or die "Could not open file '$partFileName' $!";
            # Overwrite it with the new AST dump
            print $fileHandle $1;
            # Close the output file
            close $fileHandle;
        }

        # By now all the output files have been created except for the last one. Let's create it:
        # Increase the filename counter
        $i = $i + 1;
        # Form the output file name
        $partFileName = "$pathWithoutExtension-$i.$astDumpExtension";
        print "Processing $partFileName...\n";
        # Open or create the output file
        open(my $fileHandle, '>', "$partFileName") or die "Could not open file '$partFileName' $!";
        # Overwrite it with the remainder of the AST dump
        print $fileHandle $astDump;
        # Close the output file
        close $fileHandle;
    }
}

print "Done!\n";
