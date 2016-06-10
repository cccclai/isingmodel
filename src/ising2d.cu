/*
Ising model: Halmitonian H = /sum_ij J(sigma_i)(sigma_j)
*/

/*
* TODO:
*   1. Calculate the energy in the program
*   2. Calculate the heat capacity in the program
*   3. Add more inputs to adjust the length of lattice
*   4. A matlab code to plot data.
*       data format example:
*                    position.x  position.y   spin(-1, 1)
*       Iteattion 1:    1           4               -1
*                       *           *                *
*                       *           *                *
*       Iteattion 2:    4           3                1
*                       *           *                *
*                       *           *                *
*       Iteattion N:    35          76               1
*                       *           *                *
*                       *           *                *
*   5. Compare the numerical value with the analytic value
*   6. Move to 3D
*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>       /* time */
#include <curand.h>
#include <curand_kernel.h>

/*
* LATTICE_LENGTH is the length of the lattice
* LATTICE_LENGTH is the number of element is one lattice
* BOLTZMANN_CONST is bolzmann constant. It is set to 1.
*/

#define  LATTICE_LENGTH 256
#define  LATTICE_2 (LATTICE_LENGTH * LATTICE_LENGTH)
#define  BOLTZMANN_CONST 1
#define  N LATTICE_LENGTH
#define  TIME_LENGTH 1e6

__global__ void printstate(double *energy);
__device__ double local_energy(int up, int down, int left, int right, int center);
__global__ void updateEnergy(int* lattice, double* energy, int init);
__global__ void update_random(int* lattice, double* random, const unsigned int offset, double beta);
__global__ void update(int* lattice, const unsigned int offset, double beta, curandState* state);

__global__ void ini_rng(curandState *state, unsigned long seed);


__global__ void ini_rng(curandState *state, unsigned long seed){
    const unsigned int idx = blockIdx.x * blockDim.y + threadIdx.x;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y;
    curand_init(seed, idx + idy * N, 0, &state[idx + idy * N]);
}


/*
*   update is the function to update a point
*   1. flip a point (1 -> -1 or -1 -> 1)
*   2. compare the energy before flip a point and after flip a point
*   3. if the energy with flipped point is small, accept
*   4. if the energy is larger, generate a random number pro_rand (0,1),
*      if pro_rand < e^(-beta * delatE), aceept. else reject.
*/

__global__ void update(int* lattice, const unsigned int offset, double beta, curandState* state){
    // Calculate the global index
    // Calculate the global index for the up, down, left, right index.
    const unsigned int idx = blockIdx.x * blockDim.y + threadIdx.x;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y;
    const unsigned int idx_l = (idx - 1 + N) % N;
    const unsigned int idx_r = (idx + 1 + N) % N;
    const unsigned int idy_u = (idy - 1 + N) % N;
    const unsigned int idy_d = (idy + 1 + N) % N;
    int flip, up, down, left, right, center;
    double pro_rand;
    double deltaE;

    // To generate random number in cuda
    curandState local_state = state[idx + idy * N];
    pro_rand = curand_uniform(&local_state);
    state[idx + idy * N] = local_state;

    if (idx < N && idy < N && idx_l < N && idx_r < N && idy_u < N && idy_d < N){
        if( ((idx + idy) % 2 == 0 && offset == 0) || ((idx + idy) % 2 == 1 && offset == 1) ){

            up = lattice[idx + idy_u * N];
            down = lattice[idx + idy_d * N];
            left = lattice[idx_l + idy * N];
            right = lattice[idx_r + idy * N];
            center = lattice[idx + idy * N];

            // Flip the center element
            flip = -center;
            // Calculate the difference between these two state
            deltaE = local_energy(up, down, left, right, flip);
            deltaE -= local_energy(up, down, left, right, center);

            // If deltaE < 0 or pro_rand <= e^(-beta * deltaE), accept new value
            if (pro_rand <= exp(- beta * deltaE)){
                lattice[idx + idy * N ] = flip;
            }
        }
    }
}

/*
*   printstate is the function to print the whole matrix.
*   Since it prints in parallel, we also print the global
*   index of the matrx.
*   it prints (x, y, (1 or -1)).
*/
__global__ void printstate(double* energy) {
    const unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y;

    if (idx < N && idy < N){
        printf("%d, %d, %f\n", idx, idy, energy[idx + idy * N]);
    }
}

/*
*   energy is the function used to calculate the energy between
*   (center, up), (center, down), (center, left), (center, right)
*/
__device__ double local_energy(int up, int down, int left, int right, int center){
    return -center * (up + down + left + right);
}

__global__ void updateEnergy(int* lattice, double* energy, double* energy2, double* mag,double* mag2, int init){

    const unsigned int idx = blockIdx.x * blockDim.y + threadIdx.x;
    const unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y;
    const unsigned int idx_l = (idx - 1 + N) % N;
    const unsigned int idx_r = (idx + 1 + N) % N;
    const unsigned int idy_u = (idy - 1 + N) % N;
    const unsigned int idy_d = (idy + 1 + N) % N;
    int up, down, left, right, center;
    double site_E;

    up = lattice[idx + idy_u * N];
    down = lattice[idx + idy_d * N];
    left = lattice[idx_l + idy * N];
    right = lattice[idx_r + idy * N];
    center = lattice[idx + idy * N];

    if (idx < N && idy < N){
        site_E = local_energy(up, down, left, right, center) / 2.0;

        if(init == 1){
            energy[idx + N * idy] = 1.0 * site_E / (TIME_LENGTH + 1);
            energy2[idx + N * idy] = 1.0 * site_E * site_E / (TIME_LENGTH + 1);
            mag[idx + N * idy] = 1.0 * center / (TIME_LENGTH + 1);
            mag2[idx + N * idy] = 1.0 * center * center / (TIME_LENGTH + 1);
        }
        else{
            energy[idx + N * idy] += 1.0 * site_E / (TIME_LENGTH + 1);
            energy2[idx + N * idy] += 1.0 * site_E * site_E / (TIME_LENGTH + 1);
            mag[idx + N * idy] += 1.0 * center / (TIME_LENGTH + 1);
            mag2[idx + N * idy] += 1.0 * center * center / (TIME_LENGTH + 1);
        }
    }
}

/*
*   Commandline inputs option
*   1. Tempurature (T)
*
*/
int main (int argc, char *argv[]){

    int *lattice;
    int *d_lattice;

    double *energy;
    double *d_energy;

    double *energy2;
    double *d_energy2;

    double *mag;
    double *d_mag;

    double *mag2;
    double *d_mag2;

    curandState *d_states;

    double T = 2;
    int warmsteps = 1e4;
    int nout = TIME_LENGTH;
    // int warp = 1e3;

    int numthreadx = 16;
    int numthready = 16;
    int numblocksX = LATTICE_LENGTH / numthreadx;
    int numblocksY = LATTICE_LENGTH / numthready;

    // First input: Tempurature. Usually between (1, 6),
    // Critical Tempurature is around 2.2
    T = argc > 1 ? atof(argv[1]) : 2;

    // Define the size of lattice and energy
    const size_t bytes_int = LATTICE_2 * sizeof(int);
    const size_t bytes_double = LATTICE_2 * sizeof(double);

    // Allocate memory for lattice. It is a lattice^2 long array.
    // The value can only be 1 or -1.
    lattice = (int*)malloc(LATTICE_2 * sizeof(int));
    energy = (double*)malloc(LATTICE_2 * sizeof(double));
    energy2 = (double*)malloc(LATTICE_2 * sizeof(double));
    mag = (double*)malloc(LATTICE_2 * sizeof(double));
    mag2 = (double*)malloc(LATTICE_2 * sizeof(double));

    // initialize lattice by rand(-1, 1)
    for(int i = 0; i < LATTICE_2; i++){
        lattice[i] = 2 * (rand() % 2) - 1;
        energy[i] = 0.0;
        energy2[i] = 0.0;
        mag[i] = 0.0;
        mag2[i] = 0.0;
    }

    // Set dimensions of block and grid
    dim3 grid(numblocksX, numblocksY, 1);
    dim3 thread(numthreadx, numthready,1);

    // beta is a parameter in the probability
    double beta = 1.0 / BOLTZMANN_CONST / T;

    // Allocate memoery in device and copy from host to device
    cudaMalloc((void **)&d_lattice, bytes_int);
    cudaMalloc((void **)&d_energy, bytes_double);
    cudaMalloc((void **)&d_energy2, bytes_double);
    cudaMalloc((void **)&d_mag, bytes_double);
    cudaMalloc((void **)&d_mag2, bytes_double);
    cudaMalloc((void **)&d_states, LATTICE_2 * sizeof(curandState));

    cudaMemcpy(d_lattice, lattice, bytes_int, cudaMemcpyHostToDevice);
    cudaMemcpy(d_energy, energy, bytes_double, cudaMemcpyHostToDevice);
    cudaMemcpy(d_energy2, energy2, bytes_double, cudaMemcpyHostToDevice);
    cudaMemcpy(d_mag, mag, bytes_double, cudaMemcpyHostToDevice);
    cudaMemcpy(d_mag2, mag2, bytes_double, cudaMemcpyHostToDevice);

    // To change the buffer size of printf; otherwise it cannot print all data
    cudaDeviceSetLimit(cudaLimitPrintfFifoSize, N * N * sizeof(int) * N);

    ini_rng<<<grid, thread>>>(d_states, time(NULL));

    // Warmup process
    for (int iter = 0; iter < warmsteps; iter++){
        update<<<grid, thread>>>(d_lattice, 0, beta, d_states);
        update<<<grid, thread>>>(d_lattice, 1, beta, d_states);
        // cudaDeviceSynchronize();
    }
    updateEnergy<<<grid, thread>>>(d_lattice, d_energy, d_energy2, d_mag, d_mag2, 1);
    // Measure process
    for (int nstep = 0; nstep < nout; nstep++){
        update<<<grid, thread>>>(d_lattice, 0, beta, d_states);
        update<<<grid, thread>>>(d_lattice, 1, beta, d_states);
        updateEnergy<<<grid, thread>>>(d_lattice, d_energy, d_energy2, d_mag, d_mag2, 0);
    }
    // printstate<<<grid, thread>>>(d_energy);
    cudaMemcpy(energy, d_energy, bytes_double, cudaMemcpyDeviceToHost);
    cudaMemcpy(energy2, d_energy2, bytes_double, cudaMemcpyDeviceToHost);
    cudaMemcpy(mag, d_mag, bytes_double, cudaMemcpyDeviceToHost);
    cudaMemcpy(mag2, d_mag2, bytes_double, cudaMemcpyDeviceToHost);

    double sum_E = 0.0;
    double sum_E2 = 0.0;
    double sum_site = 0.0;
    double sum_site2 = 0.0;
    // double sum2 = 0.0;

    for (int i = 0; i < N ; i++){
        for (int j = 0; j < N; j++){
            sum_E += energy[i + j * N];
            sum_E2 += energy2[i + j * N];
            sum_site += mag[i + j * N];
            sum_site2 += mag2[i + j * N];
        }
    }

    double aver_E = 1.0 * sum_E / LATTICE_2;
    double aver_E2 = 1.0 * sum_E2 / LATTICE_2;
    double aver_site = 1.0 * sum_site / LATTICE_2;
    double aver_site2 = 1.0 * sum_site2 / LATTICE_2;

    double heat_capacity = 1.0 * (aver_E2 - aver_E * aver_E) / T / T;
    double mag_sus = 1.0 * (aver_site2 - aver_site * aver_site) / T;

    printf("%f\n", T);
    printf("%d\n", LATTICE_LENGTH);
    printf("%f\n", aver_E);
    printf("%f\n", heat_capacity);
    printf("%f\n", fabs(aver_site));
    printf("%f\n", mag_sus );

    //
    // printf("%s\n", );
    // printf("%f\n", 0.5 * sum / LATTICE_2);
    // printstate<<<grid, thread>>>(d_energy);

    free(lattice);
    cudaFree(d_lattice);

    free(energy);
    cudaFree(d_energy);

    free(energy2);
    cudaFree(d_energy2);

    free(mag);
    cudaFree(d_mag);

    free(mag2);
    cudaFree(d_mag2);

}
