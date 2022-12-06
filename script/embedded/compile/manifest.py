import os
import sys
import shutil

import git

sys.path.insert(1, os.path.join(os.path.dirname(__file__),'../../..'))

from log import log_init

logger = log_init()

class Manifest(object):

    @staticmethod
    def get_repo_param(src_dir : str, local_dir : str):
        repoDir = os.path.join(src_dir, local_dir)
        try:
            repo = git.Repo(repoDir)
        except Exception as e:
            logger.error(e)
            return None

        with repo.config_writer('global') as config:
            config.set_value('safe', 'directory', repoDir).release()

        path = local_dir

        try:
            remote = repo.remote()
            repoName = remote.url.replace("https://gitee.com/", "")
            revision = repo.head.commit.hexsha
        except Exception as e:
            logger.error(e)
            return None

        if "src-openeuler" in remote.url:
            group = "src-openeuler"
        else:
            group = "openeuler"

        try:
            branch = repo.active_branch.name
        except TypeError:
            for tag in repo.tags:
                if tag.commit.hexsha == repo.head.commit.hexsha:
                    branch = tag.name
                    break
        except Exception as e:
            logger.error(e)
            return None
        
        return {
            'repo_name': repoName,
            'path': path,
            'revision': revision,
            'group': group,
            'branch': branch
        }

    def exec(self, src_dir):

        if os.path.exists(os.path.join(src_dir, 'manifest.xml')):
            os.remove(os.path.join(src_dir, 'manifest.xml'))

        os.mknod(os.path.join(src_dir, 'manifest.xml'))

        yocto = self.get_repo_param(src_dir, 'yocto-poky')
        if yocto == None:
            raise("there is no yocto-poky")

        with open(os.path.join(src_dir, 'manifest.xml'), 'a+') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n')
            f.write('<manifest>\n')
            f.write('    <remote name="gitee" fetch="https://gitee.com/" review="https://gitee.com/"/>\n')
            f.write('    <default revision="{}" remote="gitee" sync-j="8"/>\n'.format(yocto["branch"]))

            dirList = os.listdir(src_dir)
            for dir in dirList:
                if dir == "yocto-meta-openeuler":
                    continue
                repoParam = self.get_repo_param(src_dir, dir)
                if repoParam == None:
                    continue
                wline = "    <project name=\"{}\" path=\"{}\" revision=\"{}\" groups=\"{}\" upstream=\"{}\"/>".format(repoParam['repo_name'], repoParam['path'], repoParam['revision'], repoParam['group'], repoParam['branch'])
                f.write(wline+"\n")

            wline = "    <project name=\"{}\" path=\"{}\" revision=\"{}\" groups=\"{}\" upstream=\"{}\"/>".format(yocto['repo_name'], yocto['path'], yocto['revision'], yocto['group'], yocto['branch'])
            f.write("</manifest>")

def main():
    if sys.argv[1:2] == "":
        raise("please entry src directory")
    logger.info("param is {}".format(sys.argv[1]))
    manifest = Manifest()
    manifest.exec(src_dir = sys.argv[1])
    logger.info("manifest create successful in {}".format(sys.argv[1]))

if __name__ == "__main__":
    main()