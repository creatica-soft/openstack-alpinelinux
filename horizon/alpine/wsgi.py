#!/usr/bin/python3

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
WSGI config for openstack_dashboard project.
"""

import os, sys, argparse, bjoern
from django.core.wsgi import get_wsgi_application

# Add this file path to sys.path in order to import settings
sys.path.insert(0, os.path.normpath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '..')))
os.environ['DJANGO_SETTINGS_MODULE'] = 'openstack_dashboard.settings'

parser = argparse.ArgumentParser(
    description='horizon openstack dashboard',
    formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    usage='%(prog)s [-h] [--port PORT] [--host IP] -- [passed options]')
parser.add_argument('--port', '-p', type=int, default=5000, help='TCP port to listen on')
parser.add_argument('--host', '-b', default='', help='IP to bind the server to')
parser.add_argument('args',
                    nargs=argparse.REMAINDER,
                    metavar='-- [passed options]',
                    help="'--' is the separator of the arguments used "
                    "to start the WSGI server and the arguments passed "
                    "to the WSGI application.")
args = parser.parse_args()
if args.args:
    if args.args[0] == '--':
        args.args.pop(0)
    else:
        parser.error("unrecognized arguments: %s" % ' '.join(args.args))
sys.argv[1:] = args.args

app = get_wsgi_application()

print("STARTING server django.core.wsgi.horizon")
url = "http://%s:%d/" % (args.host, args.port)
print("Available at %s" % url)
sys.stdout.flush()

bjoern.run(app, args.host, args.port)
