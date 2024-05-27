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
forecasts = zeros(60,24)
println(forecasts)
for i in 1:60 
    for j in 1:24
        mu = 10     #acá tomar valor del excel
        if (1==1)   #acá incluir si es solar o eólica
            sigma = mu*(max_k_wind-min_k_wind)/(24-1)
        else
            sigma = mu*(max_k_sun-min_k_sun)/(24-1)
        end
        sim_norm = rand(Normal(mu,sigma))
        forecasts[i,j] = sim_norm
    end
end   

println(forecasts)
