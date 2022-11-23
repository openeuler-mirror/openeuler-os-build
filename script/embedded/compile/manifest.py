import os
import sys

import git

class Manifest(object):

    @staticmethod
    def get_repo_param(repo_dir : str):
        try:
            repo = git.Repo(repo_dir)
        except:
            return None
            
        path = dir
        remote = repo.remote()
        repoName = remote.url.replace("https://gitee.com/", "")
        revision = repo.head.commit
        if "src-openeuler" in remote.url:
            group = "src-openeuler"
        else:
            group = "openeuler"

        try:
            branch = repo.active_branch.name
        except TypeError:
            for tag in repo.tags:
                if tag.commit == repo.head.commit:
                    branch = tag.name
                    break
        except Exception as e:
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

        yocto = self.get_repo_param(repo_dir = os.path.join(src_dir, 'yocto-meta-openeuler'))
        if yocto == None:
            raise("there is no yocto-meta-openeuler")

        with open(os.path.join(src_dir, 'manifest.xml'), 'a+') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n')
            f.write('<manifest>\n')
            f.write('    <remote name="gitee" fetch="https://gitee.com/" review="https://gitee.com/"/>\n')
            f.write('    <default revision="{}" remote="gitee" sync-j="8"/>\n'.format(yocto["branch"]))

            dirList = os.listdir(src_dir)
            for dir in dirList:
                if dir == "yocto-meta-openeuler":
                    continue
                repoParam = self.get_repo_param(repo_dir = os.path.join(src_dir, dir))
                if repoParam == None:
                    continue
                wline = "    <project name=\"{}\" path=\"{}\" revision=\"{}\" groups=\"{}\" upstream=\"{}\"/>".format(repoParam['repo_name'], repoParam['path'], repoParam['revision'], repoParam['group'], repoParam['branch'])
                f.write(wline+"\n")

            wline = "    <project name=\"{}\" path=\"{}\" revision=\"{}\" groups=\"{}\" upstream=\"{}\"/>".format(yocto['repo_name'], yocto['path'], yocto['revision'], yocto['group'], yocto['branch'])
            f.write("</manifest>")

def main():
    if sys.argv[1:2] == "":
        raise("please entry src directory")

    manifest = Manifest()
    manifest.exec(src_dir = sys.argv[1:2])
    print("manifest create successful in {}".format(sys.argv[1:2]))

if __name__ == "__main__":
    main()