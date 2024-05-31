#Importar paquetes
using Random, Distributions, Plots
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi
using XLSX  # Se agrega para leer archivos .xlsx (Excel)

#Random.seed!(1234) #para que las simulaciones de prueba sean consistentes

#Lectura de excel
archivo = "Case118.xlsx"    # se comienza con el caso mas pequeño
xf = XLSX.readxlsx(archivo) # leer el archivo excel

# Separar hojas del archivo
sheet_buses = xf["Buses"]
sheet_demandas = xf["Demand"]
sheet_generadores = xf["Generators"]
sheet_lineas = xf["Lines"]
sheet_renovables = xf["Renewables"]

# Definir la función de parada
# Se crea el DataFrame hasta que se reconozca la entrada "END"
# De esta forma se puede leer tablas con cualquier numero de filas
#   siempre y cuando terminen con un "END".
function stop_condition(row)
    return isempty(row[1]) || row[1] == "END"
end
renovables_ref  = DataFrame(XLSX.gettable(sheet_renovables,"A:Y",first_row=2,stop_in_row_function=stop_condition))
renewables = copy(renovables_ref) 
#println(renewables)

# inicio simulaciones
iteraciones = 100
min_k_wind = 14.70 / 100
max_k_wind = 30.92 / 100
min_k_sun = 10.20 / 100
max_k_sun = 14.02 / 100

#estas listas tendrán 24 listas. Estos vectores se graficarán
horas_eol = []
horas_sun = []
horas_sist = []
for _ in 1:24
    push!(horas_eol, 0)
    push!(horas_sun, 0)
    push!(horas_sist, 0)
end


#Cada uno de estos vectores incluye los 100 escenarios para una hora dada
esc_eol = []
esc_sun = []
esc_sist = []
for _ in 1:24
    push!(esc_eol, 0)
    push!(esc_sun, 0)
    push!(esc_sist, 0)
    
end



for e in 1:100    
    for t in 1:24
        tot_sun=0
        tot_eol=0
        tot_sist=0
        for g in 1:60
            mu = renewables[g,t+1]                      #acá toma valor del excel
            if (g<=40)                                  #acá revisa si es solar o eólica
                me=(max_k_wind-min_k_wind)/(24-1)
                sigma = mu*(t*me+min_k_wind-me)
            else
                ms=(max_k_sun-min_k_sun)/(24-1)
                sigma = mu*(t*ms+min_k_sun-ms)
            end
            sim_norm = mu + rand(Normal(0,sigma))       
            if (sim_norm<0)                             #trunca valores negativos
                sim_norm = 0
            end
            if (g<=40)
                tot_eol+=sim_norm
                #var_eol[t] += sigma^2/100
            else
                tot_sun+=sim_norm
                #var_sun[t] += sigma^2/100
            end
            tot_sist+=sim_norm  
        end
        esc_eol[t]=tot_eol
        esc_sun[t]=tot_sun
        esc_sist[t]=tot_sist
    end
    global horas_eol = hcat(horas_eol,esc_eol)
    global horas_sun = hcat(horas_sun,esc_sun)
    global horas_sist = hcat(horas_sist,esc_sist)
end

pl_eol = Float64.(horas_eol[:, 1:end .!= 1])
pl_sun = Float64.(horas_sun[:, 1:end .!= 1])
pl_sist = Float64.(horas_sist[:, 1:end .!= 1])
#println(Float64.(horas_eol[:, 1:end .!= 1]))
#println(pl_eol)

horas = 1:24


#variables para creación de curva de medias.
# Y variables para los intervalos de confianza

mean_eol = []
mean_sun = []
mean_sist = []
var_eol = []
var_sun = []
p90 = 1.645
p99 = 2.575
IC90upE = []
IC90downE = []
IC99upE = []
IC99downE = []
IC90upS = []
IC90downS = []
IC99upS = []
IC99downS = []
IC90upT = []
IC90downT = []
IC99upT = []
IC99downT = []

for _ in 1:24
    push!(mean_eol, 0)
    push!(mean_sun, 0)
    push!(mean_sist, 0)
    push!(var_eol, 0)
    push!(var_sun, 0)
    push!(IC90upE, 0)
    push!(IC90downE, 0)
    push!(IC99upE, 0)
    push!(IC99downE, 0)
    push!(IC90upS, 0)
    push!(IC90downS, 0)
    push!(IC99upS, 0)
    push!(IC99downS, 0)
    push!(IC90upT, 0)
    push!(IC90downT, 0)
    push!(IC99upT, 0)
    push!(IC99downT, 0)
end
    
for t in 1:24
    tot_sun=0
    tot_eol=0
    tot_sist=0
    me=(max_k_wind-min_k_wind)/(24-1)
    ms=(max_k_sun-min_k_sun)/(24-1)
    for g in 1:60
        mu = renewables[g,t+1]                      #acá toma valor del excel 
        if (g<=40)                                  #acá revisa si es solar o eólica 
            sigma = mu*(t*me+min_k_wind-me)
            tot_eol+=mu
            var_eol[t] += sigma^2
        else
            sigma = mu*(t*ms+min_k_sun-ms)
            tot_sun+=mu
            var_sun[t] += sigma^2
        end
        tot_sist+=mu  
    end
    mean_eol[t] = tot_eol
    mean_sun[t] = tot_sun
    mean_sist[t] = tot_sist
    IC90upE[t] = tot_eol + sqrt(var_eol[t])*p90
    IC90downE[t] = tot_eol - sqrt(var_eol[t])*p90
    IC99upE[t] = tot_eol + sqrt(var_eol[t])*p99
    IC99downE[t] = tot_eol - sqrt(var_eol[t])*p99
    IC90upS[t] =  tot_sun + sqrt(var_sun[t])*p90
    IC90downS[t] = tot_sun - sqrt(var_sun[t])*p90
    IC99upS[t] = tot_sun + sqrt(var_sun[t])*p99
    IC99downS[t] = tot_sun - sqrt(var_sun[t])*p99
    IC90upT[t] = tot_sist + sqrt(var_sun[t]+var_eol[t])*p90
    IC90downT[t] = tot_sist - sqrt(var_sun[t]+var_eol[t])*p90
    IC99upT[t] = tot_sist + sqrt(var_sun[t]+var_eol[t])*p99
    IC99downT[t] = tot_sist - sqrt(var_sun[t]+var_eol[t])*p99
end
#print(Float64.(mean_eol))

#=
plot(horas, pl_eol, title = "Predicciones Eolicas", legend = false, palette = :Accent_5)
plot!(horas, Float64.(mean_eol),  legend = false, lw=3, lc=:black)
plot!(horas, Float64.(IC90upE),  legend = false, lw=2, lc=:red)
plot!(horas, Float64.(IC90downE), legend = false, lw=2, lc=:red)
plot!(horas, Float64.(IC99upE), legend = false, lw=2, lc=:lightgreen)
plot!(horas, Float64.(IC99downE), legend = false, lw=2, lc=:lightgreen)
=#


plot!(horas, pl_sun, title = "Predicciones Solares", legend = false, palette = :Accent_5)
plot!(horas, Float64.(mean_sun),  legend = false, lw=3, lc=:red)
plot!(horas, Float64.(IC90upS),  legend = false, lw=2, lc=:black)
plot!(horas, Float64.(IC90downS),  legend = false, lw=2, lc=:black)
plot!(horas, Float64.(IC99upS),  legend = false, lw=2, lc=:gray)
plot!(horas, Float64.(IC99downS), legend = false, lw=2, lc=:gray)


#=
plot!(horas, pl_sist, title = "Predicciones Totales", legend = false, palette = :Accent_5)
plot!(horas, Float64.(mean_sist),  legend = false, lw=3, lc=:black)
plot!(horas, Float64.(IC90upT),  legend = false, lw=2, lc=:red)
plot!(horas, Float64.(IC90downT),  legend = false, lw=2, lc=:red)
plot!(horas, Float64.(IC99upT),  legend = false, lw=2, lc=:lightgreen)
plot!(horas, Float64.(IC99downT), legend = false, lw=2, lc=:lightgreen)
=#

#ylims!(0, 4000)
#xlims!(1, 24)
xlabel!("Hora")
ylabel!("Generación [MW]")