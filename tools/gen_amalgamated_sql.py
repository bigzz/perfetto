#!/usr/bin/env python3
# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import os
import sys

# Converts the SQL metrics for trace processor into a C++ header with the SQL
# as a string constant to allow trace processor to exectue the metrics.

REPLACEMENT_HEADER = '''/*
 * Copyright (C) 2022 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 *******************************************************************************
 * AUTOGENERATED BY tools/gen_merged_sql_metrics - DO NOT EDIT
 *******************************************************************************
 */

 #include <string.h>
'''

NAMESPACE_BEGIN = '''
namespace perfetto {{
namespace trace_processor {{
namespace {} {{
'''

NAMESPACE_END = '''
}}  // namespace {}
}}  // namespace trace_processor
}}  // namespace perfetto
'''

FILE_TO_SQL_STRUCT = '''
struct FileToSql {
  const char* path;
  const char* sql;
};
'''

def filename_to_variable(filename):
  return "k" + "".join([x.capitalize() for x in filename.split("_")])


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--namespace', required=True)
  parser.add_argument('--cpp-out', required=True)
  parser.add_argument('--input-list-file')
  parser.add_argument('--root-dir', required=True)
  parser.add_argument('sql_files', nargs='*')
  args = parser.parse_args()

  if args.input_list_file and args.sql_files:
    print("Only one of --input-list-file and list of SQL files expected")
    return 1

  sql_files = []
  if args.input_list_file:
    with open(args.input_list_file, 'r') as input_list_file:
      for line in input_list_file.read().splitlines():
        sql_files.append(line)
  else:
    sql_files = args.sql_files

  # Extract the SQL output from each file.
  sql_outputs = {}
  for file_name in sql_files:
    with open(file_name, 'r') as f:
      relpath = os.path.relpath(file_name, args.root_dir)
      sql_outputs[relpath] = "".join(
          x.lstrip() for x in f.readlines() if not x.lstrip().startswith('--'))

  with open(args.cpp_out, 'w+') as output:
    output.write(REPLACEMENT_HEADER)
    output.write(NAMESPACE_BEGIN.format(args.namespace))

    # Create the C++ variable for each SQL file.
    for path, sql in sql_outputs.items():
      name = os.path.basename(path)
      variable = filename_to_variable(os.path.splitext(name)[0])
      output.write('\nconst char {}[] = '.format(variable))
      # MSVC doesn't like string literals that are individually longer than 16k.
      # However it's still fine "if" "we" "concatenate" "many" "of" "them".
      # This code splits the sql in string literals of ~1000 chars each.
      line_groups = ['']
      for line in sql.split('\n'):
        line_groups[-1] += line + '\n'
        if len(line_groups[-1]) > 1000:
          line_groups.append('')

      for line in line_groups:
        output.write('R"_d3l1m1t3r_({})_d3l1m1t3r_"\n'.format(line))
      output.write(';\n')

    output.write(FILE_TO_SQL_STRUCT)

    # Create mapping of filename to variable name for each variable.
    output.write("\nconst FileToSql kFileToSql[] = {")
    for path in sql_outputs.keys():
      name = os.path.basename(path)
      variable = filename_to_variable(os.path.splitext(name)[0])

      # This is for Windows which has \ as a path separator.
      path = path.replace("\\", "/")
      output.write('\n  {{"{}", {}}},\n'.format(path, variable))
    output.write("};\n")

    output.write(NAMESPACE_END.format(args.namespace))

  return 0


if __name__ == '__main__':
  sys.exit(main())
