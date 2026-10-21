#!/usr/bin/env python
from datetime import datetime
import sys, cStringIO as StringIO
import random
import time
import xmlrpclib, urllib, urlparse, socket
from datetime import datetime
import os
import pwd
import getpass
import re
from urlparse import uses_netloc
uses_netloc.append('scgi')

# PID-based lock
lockfile_path = "/tmp/script.lock"

def acquire_lock(lockfile):
    if os.path.exists(lockfile):
        with open(lockfile, 'r') as f:
            pid = f.read().strip()
        if os.path.exists("/proc/{}".format(pid)):
            print("Script is already running with PID {}. Exiting.".format(pid))
            sys.exit(0)
        else:
            print("Stale lock file found. Overwriting with new PID.")
    
    with open(lockfile, 'w') as f:
        f.write(str(os.getpid()))

def release_lock(lockfile):
    if os.path.exists(lockfile):
        os.remove(lockfile)

def do_scgi_xmlrpc_request(host, methodname, params=()):
    xmlreq = xmlrpclib.dumps(params, methodname)
    xmlresp = SCGIRequest(host).send(xmlreq)
    return xmlresp

def do_scgi_xmlrpc_request_py(host, methodname, params=()):
    xmlresp = do_scgi_xmlrpc_request(host, methodname, params)
    return xmlrpclib.loads(xmlresp)[0][0]

class SCGIRequest(object):
    def __init__(self, url):
        self.url = url
        self.resp_headers = []
    def __send(self, scgireq):
        scheme, netloc, path, query, frag = urlparse.urlsplit(self.url)
        host, port = urllib.splitport(netloc)
        if netloc:
            addrinfo = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
            assert len(addrinfo) == 1, "There's more than one? %r" % addrinfo
            sock = socket.socket(*addrinfo[0][:3])
            sock.connect(addrinfo[0][4])
        else:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(path)
        sock.send(scgireq)
        recvdata = resp = sock.recv(1024)
        while recvdata != '':
            recvdata = sock.recv(1024)
            resp += recvdata
        sock.close()
        return resp
    def send(self, data):
        "Send data over scgi to url and get response"
        scgiresp = self.__send(self.add_required_scgi_headers(data))
        resp, self.resp_headers = self.get_scgi_resp(scgiresp)
        return resp
    @staticmethod
    def encode_netstring(string):
        "Encode string as netstring"
        return '%d:%s,' % (len(string), string)
    @staticmethod
    def make_headers(headers):
        "Make scgi header list"
        return '\x00'.join(['%s\x00%s' % t for t in headers]) + '\x00'
    @staticmethod
    def add_required_scgi_headers(data, headers=[]):
        "Wrap data in an scgi request, see spec at: http://python.ca/scgi/protocol.txt"
        headers = SCGIRequest.make_headers(
            [('CONTENT_LENGTH', str(len(data))), ('SCGI', '1')] + headers
        )
        enc_headers = SCGIRequest.encode_netstring(headers)
        return enc_headers + data
    @staticmethod
    def gen_headers(file):
        "Get header lines from scgi response"
        line = file.readline().rstrip()
        while line.strip():
            yield line
            line = file.readline().rstrip()
    @staticmethod
    def get_scgi_resp(resp):
        "Get xmlrpc response from scgi response"
        fresp = StringIO.StringIO(resp)
        headers = []
        for line in SCGIRequest.gen_headers(fresp):
            headers.append(line.split(': ', 1))
        xmlresp = fresp.read()
        return (xmlresp, headers)

class RTorrentXMLRPCClient(object):
    def __init__(self, url, methodname=''):
        self.url = url
        self.methodname = methodname
    def __call__(self, *args):
        scheme, netloc, path, query, frag = urlparse.urlsplit(self.url)
        xmlreq = xmlrpclib.dumps(args, self.methodname)
        if scheme == 'scgi':
            xmlresp = SCGIRequest(self.url).send(xmlreq)
            return xmlrpclib.loads(xmlresp)[0][0]
        elif scheme == 'http':
            raise Exception('Unsupported protocol')
        elif scheme == '':
            raise Exception('Unsupported protocol')
        else:
            raise Exception('Unsupported protocol')
    def __getattr__(self, attr):
        methodname = self.methodname and '.'.join([self.methodname, attr]) or attr
        return RTorrentXMLRPCClient(self.url, methodname)

def convert_params_to_native(params):
    "Parse xmlrpc-c command line arg syntax"
    cparams = []
    for param in params:
        if len(param) < 2 or param[1] != '/':
            cparams.append(param)
            continue
        if param[0] == 'i':
            ptype = int
        elif param[0] == 'b':
            ptype = bool
        elif param[0] == 's':
            ptype = str
        else:
            cparams.append(param)
            continue
        cparams.append(ptype(param[2:]))
    return tuple(cparams)

def is_private(url):
    pattern1 = '(http|https|udp)://[a-z0-9\.-]+\.[a-z]{2,13}((:[0-9]{2,5})|)/.*an.*\?.+=.+'
    pattern2 = '(http|https|udp)://[a-z0-9\.-]+\.[a-z]{2,13}((:[0-9]{2,5})|)/.*[0-9a-zA-Z]{8,32}/an.*'
    result = True if re.match(pattern1, url) or re.match(pattern2, url) else False
    return result

def check_torrent(hash):
    host = os.path.abspath('/torrents/config/rtorrent/.rtorrent.sock')
    try:
        methodname = 'd.get_state'
        respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
        torrent_active = bool(xmlrpclib.loads(respxml)[0][0])
        methodname = 'd.get_complete'
        respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
        torrent_complete = bool(xmlrpclib.loads(respxml)[0][0])
        methodname = 'd.is_private'
        respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
        torrent_private = bool(xmlrpclib.loads(respxml)[0][0])
        if torrent_active and torrent_complete and not torrent_private:
            methodname = 'd.get_tracker_size'
            respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
            tracker_cnt = xmlrpclib.loads(respxml)[0][0]
            is_public = True
            for t in range(0, tracker_cnt):
                methodname = 't.get_url'
                respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash), 'i/{}'.format(t)]))
                tracker = xmlrpclib.loads(respxml)[0][0]
                if is_private(tracker):
                    is_public = False
                    break
            if is_public:
                methodname = 'd.try_close'
                respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
                result = not bool(xmlrpclib.loads(respxml)[0][0])
                if result:
                    print('{} {} stoppped.'.format(datetime.now().isoformat(), hash))
    except xmlrpclib.Fault as e:
        print 'ERROR: ', e

def get_torrents():
    host = os.path.abspath('/torrents/config/rtorrent/.rtorrent.sock')
    try:
        methodname = 'download_list'
        respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format('')]))
        download_list = xmlrpclib.loads(respxml)[0][0]
        return download_list
    except xmlrpclib.Fault as e:
        print 'ERROR: ', e

def remove_torrent(hash):
    """
    Try to remove the torrent with the given SHA1 hash by calling the 'd.erase' XMLRPC method directly.
    If the torrent doesn't exist (or removal fails), catch the error.
    """
    host = os.path.abspath('/torrents/config/rtorrent/.rtorrent.sock')
    try:
        methodname = 'd.erase'
        respxml = do_scgi_xmlrpc_request(host, methodname, convert_params_to_native(['s/{}'.format(hash)]))
        # Assume that a successful removal returns a value that evaluates to False.
        result = not bool(xmlrpclib.loads(respxml)[0][0])
        if result:
            print('{} {} removed.'.format(datetime.now().isoformat(), hash))
        else:
            print('{} {} removal failed.'.format(datetime.now().isoformat(), hash))
    except xmlrpclib.Fault as e:
        print("Torrent with hash {} not found or removal error. Error: {}".format(hash, e))

def daemon_loop():
    while True:
        torrents = get_torrents()
        if torrents and len(torrents) > 0:
            print('{} torrent(s) found.'.format(len(torrents)))
            for torrent in torrents:
                print('Checking: {}'.format(torrent))
                check_torrent(torrent)
        else:
            print('No torrents found, do nothing.')
        jitter = random.randint(60, 120)
        print("Delaying next execution by {} seconds.".format(jitter))
        time.sleep(jitter)

if __name__ == "__main__":
    # If a SHA1 hash is provided as an argument, then remove the torrent with that hash
    # and exit immediately without acquiring any locks.
    if len(sys.argv) > 1:
        if len(sys.argv) != 2:
            print("Usage: {} [SHA1_HASH]".format(sys.argv[0]))
            sys.exit(1)
        hash_arg = sys.argv[1]
        if not re.match(r'^[0-9a-fA-F]{40}$', hash_arg):
            print("Invalid SHA1 hash format: {}. Must be 40 hexadecimal characters.".format(hash_arg))
            sys.exit(1)
        remove_torrent(hash_arg)
        sys.exit(0)
    acquire_lock(lockfile_path)
    daemon_loop()
    release_lock(lockfile_path)