import os, platform
import numpy

from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
import glob

try:
    #check for tubo jpeg offical lib and select appropriate lib32/lib64 path.
    tj_lib = glob.glob('/opt/libjpeg-turbo/lib*')[0]+'/libturbojpeg.a'
except IndexError:
   raise Exception("Please install libturbojpeg")

extensions = [
    Extension(  name="v4l2",
                sources=['v4l2.pyx'],
                include_dirs =  [numpy.get_include()],
                libraries = ['v4l2','rt'],
                extra_link_args=[],
                extra_objects = [tj_lib],
                extra_compile_args=[]
            ),
]

setup(  name="v4l2",
        version="0.1", #make sure this is the same in v4l2.pxy
        description="V4L2 bindings with format conversion tool (3P Tecnologia's support for Qualcomm Dragonboard 410c).",
        ext_modules=cythonize(extensions, compiler_directives={'language_level' : "3"})
)
