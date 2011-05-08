use inc::Module::Install;
name 'Net-Okuyama';
all_from 'lib/Net/Okuyama.pm';

requires 'MIME::Base64';

test_requires 'Test::Requires';
test_requires 'Test::TCP';

readme_markdown_from 'lib/Net/Okuyama.pm';
tests 't/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
author_tests('xt');
WriteAll;
