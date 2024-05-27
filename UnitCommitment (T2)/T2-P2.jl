#Importar librerias
using Random, Distributions, Plots
#Lectura de excel


# inicio simulaciones
iteraciones = 100
min_k_wind = 14.70
max_k_wind = 30.92
min_k_sun = 10.20
max_k_sun = 14.02

# 40 eolicas 20 solares
forecasts = []
for i in 1:60
    ist = [] 
    for i in 1:24
        l
        mu =
        if (==wind)
            sigma = (max_k_wind-min_k_wind)/(24-1)
        else
            sigma = (max_k_sun-min_k_sun)/(24-1)
        end
        sim_norm = rand(Normal(mu,sigma))
        list=hcat(list,sim_norm)
    end
    forecasts=vcat(forecasts,list)
end   
