/*
Ising model: Halmitonian H = /sum_ij J(sigma_i)(sigma_j)
We set J = 1 first

*/
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>       /* time */
#include <curand.h>
#include <curand_kernel.h>

#define  LATTICE_LENGTH 256
#define  LATTICE_2 (LATTICE_LENGTH * LATTICE_LENGTH)
#define  BOLTZMANN_CONST 1
#define  BLOCK_SIZE 256
#define  N LATTICE_LENGTH

__device__ int energy(int up, int down, int left, int right, int center);
__global__ void update(int *lattice, unsigned int offset);
__global__ void printstate(int *lattice);

__global__ void update(int* lattice, const unsigned int offset, double beta){
    const unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y + offset;
    const unsigned int idx_l = (idx - 1 + N) % N;
    const unsigned int idx_r = (idx + 1 + N) % N;
    const unsigned int idy_u = (idy - 1 + N) % N;
    const unsigned int idy_d = (idy + 1 + N) % N;

    if (idx < N && idy < N && idx_l < N && idx_r < N && idy_u < N && idy_d < N){
        int new;
        double deltaE;
        curandState_t state1;
        curantState_t state2;
        curand_init(idx, idx + 1, 0, &state1);
        curand_init(idy, idy + 1, 0, &state2);

        new = 2 * (curand(&state) % 2) - 1;
        pro_rand = curand_uniform(&state);

        up = lattice[idx * N + idy_u];
        down = lattice[idx * N + idy_d];
        left = lattice[idx_l * N + idy];
        down = lattice[idx_r * N + idy];
        center = lattice[idx * N + idy];

        deltaE = energy(up, down, left, right, new);
        deltaE -= energy(up, down, left, right, center);

        if (pro_rand <= exp(- beta * deltaE)){
            lattice[idx * N + idy] = new;
        }
    }
}

__global__ void printstate(int* lattice) {
    const unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y + offset;

    if (idx < N && idy < N){
        printf("%d, %d, %d", idx, idy, lattice[idx * N + idy])
    }
}

__device__ int energy(int up, int down, int left, int right, int center){
    double H;
    H = -up * center;
    H -= down * center;
    H -= left * center;
    H -= right * center;
    return H;
}

int main (int argc, char *argv[]){

    int *lattice;
    int *d_lattice;
    double T = 2;
    int nout, mout;

    int numthreadx = 32;
    int numthready = 4;
    int numblockX = LATTICE_LENGTH / ntx;
    int numblocksY = LATTICE_LENGTH / nty;

    T = argc > 1 ? atof(argv[1]) : 2;

    const size_t bytes = LATTICE_2 * sizeof(int);
    lattice = (int*)malloc(LATTICE_2 * sizeof(int));

    for(int i = 0; i < LATTICE_2; i++){
            // lattice[i] = 2 * (rand() % 2) - 1;
            lattice[i] = 1;
    }

    // Tempurature
    dim3 grid(numblocksX, numblocksY, 1);
    dim3 threads(numthreadx, numthready,1);

    int new;
    double beta = 1.0 / BOLTZMANN_CONST / T;
    srand (time(NULL));
    // Initialize every grid point

    cudaMalloc((void **)&d_lattice, bytes);
    cudaMemcpy(d_lattice, lattice, bytes, cudaMemcpyHostToDevice);

    // Warmup process
    for (int iter = 0; iter < WARMSTEPS; iter++){
        update<<<grid, thread>>>(d_lattice, 0, beta);
        update<<<grid, thread>>>(d_lattice, 1, beta);
    }

    // Measure steps
    for (int nstep = 0; nstep < NOUT; nstep++){
        update<<<grid, block>>>(d_lattice, 0, beta);
        update<<<grid, block>>>(d_lattice, 1, beta);
        cudaDeviceSynchronize();
        printstate<<<grid, block>>>(d_lattice);
    }

    free(lattice);
    cudaFree(d_lattice);
}
