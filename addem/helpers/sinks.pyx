"""
SINKS.PYX

Created: Wed Mar 16, 2016  02:41PM
Last modified: Thu Mar 24, 2016  05:12PM

"""

import numpy as np
cimport numpy as np

INT = np.int
ctypedef np.int_t INT_t
FLOAT = np.float64
ctypedef np.float64_t FLOAT_t

def hello():
    """says hello"""
    print "Hello! I am the 'addem.helpers.sinks' module!"
    return None

def find_single_pixel(np.ndarray[FLOAT_t, ndim=2] arr not None):
    """
    Finds single-pixel depressions in given DEM array.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef int max_ns = (nx * ny) // 9
    cdef int ns = 0
    cdef Py_ssize_t i, j, k
    cdef float m
    cdef np.ndarray[INT_t, ndim=1] row = np.zeros([max_ns], dtype=INT)
    cdef np.ndarray[INT_t, ndim=1] col = np.zeros([max_ns], dtype=INT)
    cdef np.ndarray[FLOAT_t, ndim=1] fval = np.zeros([max_ns], dtype=FLOAT)
    k = 0
    for i in range(1, nx - 1):
        for j in range(1, ny - 1):
            m = min(# minimum of neighbours
                    arr[i-1, j], arr[i+1, j],       # north & south
                    arr[i, j-1], arr[i, j+1],       # east & west
                    arr[i-1, j-1], arr[i-1, j+1],   # nw & ne
                    arr[i+1, j-1], arr[i+1, j+1]    # sw & se
                    )
            # sinks_1px := array entries which are less than min. of nbrs
            if arr[i, j] < m:
                row[k] = i
                col[k] = j
                fval[k] = m
                k += 1
                ns += 1
    row = row[:k]
    col = col[:k]
    fval = fval[:k]
    return ns, row, col, fval

def fill_single_pixel(np.ndarray[FLOAT_t, ndim=2] arr not None,
                      int ns,
                      np.ndarray[INT_t, ndim=1] row not None,
                      np.ndarray[INT_t, ndim=1] col not None,
                      np.ndarray[FLOAT_t, ndim=1] fval not None,
                      ):
    """
    Fills single-pixel depressions in given DEM array.
    """
    cdef Py_ssize_t k
    cdef float m
    cdef np.ndarray[FLOAT_t, ndim=1] nbrs = np.zeros([8], dtype=FLOAT)
    for k in range(ns):
        arr[row[k], col[k]] = fval[k]
    return arr

def find_multi_pixel(np.ndarray[FLOAT_t, ndim=2] arr not None):
    """
    Finds multi-pixel depressions in given DEM array.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef int max_ca = arr.size
    cdef int max_ns = max_ca // 9
    cdef int ns = 0
    cdef Py_ssize_t i, j, k
    cdef float m
    cdef list sinks = [0] * max_ns
    cdef list catchments = [0] * max_ns
    cdef np.ndarray[FLOAT_t, ndim=1] fval = np.zeros([max_ns], dtype=FLOAT)
    cdef np.ndarray[INT_t, ndim=1] ca_row = np.zeros([max_ca], dtype=INT)
    cdef np.ndarray[INT_t, ndim=1] ca_rol = np.zeros([max_ca], dtype=INT)
    cdef list visited = []
    cdef list sink = []
    cdef float f
    k = 0
    for i in range(1, nx - 1):
        for j in range(1, ny - 1):
            if (i, j) not in visited:
                m = min(# minimum of neighbours
                        arr[i-1, j], arr[i+1, j],       # north & south
                        arr[i, j-1], arr[i, j+1],       # east & west
                        arr[i-1, j-1], arr[i-1, j+1],   # nw & ne
                        arr[i+1, j-1], arr[i+1, j+1]    # sw & se
                        )
                if arr[i, j] == m:
                    sink = [(i, j)]
                    visited = [(i, j)]
                    catch = []
                    s, c, v = plateau_at(arr, i, j, m, sink, catch, visited)
                    #catchment = []
                    #_, sink, catchment, visited = plateau_at(arr, i, j, m, 
                    #                                         sink, catchment, 
                    #                                         visited)
                    catchment, visited = sink_catchment(arr, c,
                                                        visited)
                    f, outlet = fill_value_multi_pixel(arr, catchment, sink)
                    sinks[k] = sink
                    catchments[k] = catchment
                    fval[k] = f
                    k += 1
    sinks = sinks[:k]
    catchments = catchments[:k]
    fval = fval[:k]
    return sinks, catchments, fval, outlet

def plateau_at(np.ndarray[FLOAT_t, ndim=2] arr not None, 
               int i, int j, float m,
               list sink, list catchment, list visited,
               ):
    """
    Returns the plateau region in given array starting at position i, j.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef list i_range, j_range
    cdef int ii, jj
    cdef int u, v
    cdef list locs = [0] * 9
    cdef Py_ssize_t idx_locs, k
    trapped = False
    while not trapped:
        k = 0
        i_range, j_range = neighbour_indices(i, j, nx, ny)
        for u in i_range:
            for v in j_range:
                locs[k] = (u, v)
                k += 1
        locs = locs[:k]
        idx_locs = 0
        found_new_loc = False
        while not found_new_loc and not trapped:
            if idx_locs < k:
                loc = locs[idx_locs]
                if loc not in visited:
                    if arr[loc] == m:
                        sink.append(loc)
                        i = loc[0]
                        j = loc[1]
                        found_new_loc = True
                    else:
                        catchment.append(loc)
                    visited.append(loc)
                idx_locs += 1
            else:
                trapped = True
    return sink, catchment, visited

def sink_catchment(np.ndarray[FLOAT_t, ndim=2] arr not None,
                   list catchment, list visited,
                   ):
    """
    Returns the catchment area for the given sink in the given array.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef list i_range, j_range
    cdef int ii, jj
    cdef int u, v
    cdef Py_ssize_t idx_locs, k
    trapped = False
    cdef int stop = 0
    cdef int nc = 0
    idx_locs = 0
    cdef tuple loc
    cdef list nbrs
    cdef tuple nbr
    while not trapped:
        loc = catchment[idx_locs]
        m = arr[loc]
        k = 0
        i_range, j_range = neighbour_indices(loc[0], loc[1], nx, ny)
        nbrs = [0] * 9
        for u in i_range:
            for v in j_range:
                nbrs[k] = (u, v)
                k += 1
        nbrs = nbrs[:k]
        dead_end = True
        for nbr in nbrs:
            if nbr not in visited:
                if arr[nbr] >= m:
                    dead_end= False
                    catchment.append(nbr)
                visited.append(nbr)
        nc = len(catchment)
        if dead_end:
            idx_locs += 1
        if idx_locs == nc:
            trapped = True
    return catchment, visited
#        m = arr[i, j]
#        k = 0
#        i_range, j_range = neighbour_indices(i, j, nx, ny)
#        for u in i_range:
#            for v in j_range:
#                locs[k] = (u, v)
#                k += 1
#        locs = locs[:k]
#        idx_locs = 0
#        found_new_loc = False
#        print "new round, new locs for ", i, j
#        print "catchment uptil now: ", catchment
#        while not found_new_loc and not trapped:
#            if idx_locs < k:
#                loc = locs[idx_locs]
#                if loc not in visited:
#                    if arr[loc] >= m:
#                        catchment.append(loc)
#                        i = loc[0]
#                        j = loc[1]
#                        found_new_loc = True
#                    #else:
#                    #    catchment.append(loc)
#                    visited.append(loc)
#                idx_locs += 1
#            else:
#                trapped = True
#            #print stop, loc, found_new_loc, trapped
#            stop += 1
#            if stop == 30: sys.exit()
#    return catchment, visited
#    cdef tuple loc
#    cdef int ii, jj
#    cdef list out_nbrs = []
#    cdef list o_nb
#    cdef tuple idx = ([], [])
#    cdef list sortidx
#    for loc in catchment:
#        idx[0].append(loc[0])
#        idx[1].append(loc[1])
#    sortidx = np.argsort(arr[idx]).tolist()
#    for kk in sortidx:
#        loc = catchment[kk]
#        ii = loc[0]
#        jj = loc[1]
#        o_nb, catchment, visited = out_neighbours(arr, ii, jj, 
#                                                  catchment, visited)
#        out_nbrs.extend(o_nb)
#    if out_nbrs != []:
#        o_nb, visited = sink_catchment(arr, out_nbrs, visited)
#        catchment.extend(o_nb)
#    return catchment, visited

def out_neighbours(np.ndarray[FLOAT_t, ndim=2] arr not None,
                   int i, int j,
                   list catchment, list visited,
                   ):
    """
    Returns the outward neighbours (part of same sink) for position i, j.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef float m = arr[i, j]
    cdef list out_nbr = []
    cdef list i_range, j_range
    cdef Py_ssize_t ii, jj
    if i == 0:
        i_range = range(i, i + 2)
    elif i == nx - 1:
        i_range = range(nx - 2, nx)
    else:
        i_range = range(i - 1, i + 2)
    if j == 0:
        j_range = range(j, j + 2)
    elif j == ny - 1:
        j_range = range(ny - 2, ny)
    else:
        j_range = range(j - 1, j + 2)
    for ii in i_range:
        for jj in  j_range:
            if (ii, jj) not in visited:
                if arr[ii, jj] >= m:
                    out_nbr.append((ii, jj))
                    catchment.append((ii, jj))
                visited.append((ii, jj))
    return out_nbr, catchment, visited

def fill_value_multi_pixel(np.ndarray[FLOAT_t, ndim=2] arr not None,
                           list catchment, list sink):
    """
    Returns fill value for pre-identified multi-pixel depressions.
    """
    cdef int nx = arr.shape[0]
    cdef int ny = arr.shape[1]
    cdef float m = 999999.
    cdef float fval = 999999.
    cdef list minlocs = []
    cdef tuple outlet
    cdef list border_out = []
    cdef list border_in = []
    for loc in catchment:
        i = loc[0]
        j = loc[1]
        if i == 0:
            i_range = range(i, i + 2)
        elif i == nx - 1:
            i_range = range(nx - 2, nx)
        else:
            i_range = range(i - 1, i + 2)
        if j == 0:
            j_range = range(j, j + 2)
        elif j == ny - 1:
            j_range = range(ny - 2, ny)
        else:
            j_range = range(j - 1, j + 2)
        for ii in i_range:
            for jj in j_range:
                if (ii, jj) not in sink:
                    if (ii, jj) not in catchment:
                        if (ii, jj) not in border_out:
                            border_out.append((ii, jj))
                        if (i, j) not in border_in:
                            border_in.append((i, j))
    for loc in border_out:
        if arr[loc] <= m:
            m = arr[loc]
            minlocs.append(loc)
    for loc in minlocs:
        i = loc[0]
        j = loc[1]
        if i == 0:
            i_range = range(i, i + 2)
        elif i == nx - 1:
            i_range = range(nx - 2, nx)
        else:
            i_range = range(i - 1, i + 2)
        if j == 0:
            j_range = range(j, j + 2)
        elif j == ny - 1:
            j_range = range(ny - 2, ny)
        else:
            j_range = range(j - 1, j + 2)
        for ii in i_range:
            for jj in j_range:
                if (ii, jj) in border_in:
                    if arr[ii, jj] <= fval:
                        fval = arr[ii, jj]
                        outlet = (ii, jj)
    return fval, outlet

def fill_multi_pixel(np.ndarray[FLOAT_t, ndim=2] arr not None,
                     list sinks,
                     np.ndarray[FLOAT_t, ndim=1] fval
                     ):
    """
    Fills multi-pixel depressions in given DEM array.
    """
    cdef list sink
    cdef tuple loc
    cdef int k
    cdef float f
    k = 0
    for sink in sinks:
        f = fval[k]
        for loc in sink:
            arr[loc] = f
        k += 1
    return arr

def neighbour_indices(int i, int j, int nx, int ny):
    """
    Returns indices of neighbours depending on the location of (i, j).
    """
    cdef list i_range
    cdef list j_range
    if i == 0:
        i_range = range(i, i + 2)
    elif i == nx - 1:
        i_range = range(nx - 2, nx)
    else:
        i_range = range(i - 1, i + 2)
    if j == 0:
        j_range = range(j, j + 2)
    elif j == ny - 1:
        j_range = range(ny - 2, ny)
    else:
        j_range = range(j - 1, j + 2)
    return i_range, j_range



