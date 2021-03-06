library(igraph)
library(dplyr)
library(ggplot2)
library(tidyr)
library(RColorBrewer)
library(ggExtra)
library(doParallel)
library(foreach)

SIH_function<-function(dispV=NA,species=10,numCom=100){
  #Constants####
  #N<- matrix(10,ncol=species,nrow=numCom) # Community x Species abundance matrix
  rInput<-150 #resource input
  rLoss<-10 #resource loss 
  eff<-0.2 #conversion efficiency
  mort<-0.2 #mortality
  Ext<- 0.1 #extinction Threshold
  
  ePeriod<-40000 #period of env sinusoidal fluctuations
  eAMP<-1 #amplitude of envrionment sinusoidal fluctuations
  
  Tmax<-140000 #number of time steps in Sim
  DT<- 0.08 # % size of discrete "time steps" - this is the Euler value
  
  #vectors####
  eOptimum<-1-seq(0,eAMP, by=eAMP/(species-1)) #species environmental optima
  
  #network####
  success<-F
  while(!success){
    landscape<-round(data.frame(x = runif(numCom, min = 1, max = 1000), y = runif(numCom, min = 1, max = 1000)))
    distance_mat1<-as.matrix(dist(landscape,method = "euclidean",diag = T,upper=T))
    
    distance_mat<-1*(distance_mat1<200)
    diag(distance_mat)<-0
    connections<-distance_mat
    distance_mat[upper.tri(distance_mat)]<-0
    
    graph<-as.undirected(graph.adjacency(distance_mat))
    graph<-set.vertex.attribute(graph,"x coordinate",value=landscape$x)
    graph<-set.vertex.attribute(graph,"y coordinate",value=landscape$y)
    graph<-set.edge.attribute(graph,"weight",value=distance_mat1[cbind(as.numeric(get.edgelist(graph)[,1]),  as.numeric(get.edgelist(graph)[,2]))])
    
    
    if(components(graph)$no == 1){success<-T}}
  
  envt.v<-0.5*eAMP*(sin((2*pi/ePeriod)*1+1+(landscape$y)*2*pi/1000)+1)
  
  plot.igraph(graph,layout=as.matrix(landscape), vertex.color=heat.colors(100)[1+(envt.v*99)], vertex.size=5000,vertex.label=NA, rescale=F, ylim=c(0,1000),xlim=c(0,1000))
  
  CS_exe<-'C:/"Program Files"/Circuitscape/cs_run.exe'
  
  #dispersal conditions####
  graph_circuit<-data.frame(get.edgelist(graph), E(graph)$weight)
  write.table(graph_circuit, paste("./Circuits/network_graph",r,".txt", sep="_"), row.names = FALSE, col.names = FALSE, quote = FALSE)
  write.table(V(graph)$name, paste("./Circuits/network_focal_nodes",r,".txt", sep="_"), row.names = FALSE, col.names = FALSE, quote = FALSE)
  CS_ini <- c("[circuitscape options]",            
              "data_type = network",
              "scenario = pairwise",
              paste(c("point_file =",
                      "habitat_file =",
                      "output_file ="),
                    c(paste("./Circuits/network_focal_nodes",r,".txt", sep="_"),
                      paste("./Circuits/network_graph",r,".txt", sep="_"),
                      paste("./Circuits/CS",r,".out",sep="_"))))
  
  writeLines(CS_ini, paste("./Circuits/my_ini",r,".ini", sep="_"))
  CS_run <- paste(CS_exe, paste("./Circuits/my_ini",r, ".ini", sep="_")) # Make the cmd
  system(CS_run)
  d <- read.table(paste("./Circuits/CS",r,"_resistances.out",sep="_"), row.names=1,header=TRUE)
  #d<-shortest.paths(graph_run, mode="all", weights=NULL, algorithm="automatic")
  #d_exp<-exp(-0.002*d) - diag(nrow(d))  #dispersal kernel function of the d matrix
  d_exp<-exp(-0.05*d) - diag(nrow(d))
  dispersal_matrix <- apply(d_exp, 1, function(x) x/sum(x)) #divides the d_exp matrix by the column sums to make it a conservative dispersal matrix
  rownames(dispersal_matrix)<-1:numCom
  
  calc.immigration <- function(N,a,dispersal_matrix) dispersal_matrix%*%N*rep(a,each=numCom)
  
  for(i in 1:length(dispV)){
    N<-matrix(10,numCom,species)
    R<-rep(10*(species/10),numCom) #Initial resources
    N0<-N
    R0<-R
    
    print(i)
    dispersal<-dispV[i]
    sampleV<-seq(100000,Tmax,by=100)
    Abund<-matrix(NA,species*numCom,length(sampleV))
    
    
    Meta_dyn<-data.frame(Species_sorting=rep(NA,length(sampleV)),Mass_effects=NA,Base_growth=NA)
    Species_data<-array(NA,dim=c(length(sampleV),species,2),dimnames = list(sampleV,1:species,c("Abundance","Occupancy")))
    
    for(TS in 1:Tmax){
      envt.v<-0.5*eAMP*(sin((2*pi/ePeriod)*TS+1+(landscape$y)*2*pi/1000)+1)
      consume <- 0.1*(1.5-abs(sapply(eOptimum,'-',envt.v)))
      Immigrants<-calc.immigration(N,dispersal,dispersal_matrix)
      Nt <- N*(1+DT*(eff*R*consume - dispersal - mort)) + DT*Immigrants
      
      Immigrants0<-calc.immigration(N0,0,dispersal_matrix)
      Nt0 <- N0*(1+DT*(eff*R0*consume -0 - mort)) + DT*Immigrants0
      
      Rt <- DT*rInput+R*(1-DT*(rLoss + rowSums(consume*N))) #resource step   
      Rt0 <- DT*rInput+R0*(1-DT*(rLoss + rowSums(consume*N0))) #resource step  
      
      if(sum(TS==sampleV)==1){
        sampleValue<-which(sampleV==TS)
        Abund[,sampleValue] <- c(t(N))
        
        fitness<-((N*(1+DT*(eff*R*consume - dispersal - mort)))-N)*(Nt>Ext)
        fitness_w_disp<-((N*(1+DT*(eff*R*consume - dispersal - mort)) + DT*Immigrants)-N)*(Nt>Ext)
        fitness0<-(N0*(1+DT*(eff*R0*consume - mort))-N0)*(Nt0>Ext)
        home_prod<-mean(rowSums(fitness_w_disp*(fitness>0)))
        disp_prod_ME<-mean(rowSums(fitness_w_disp*(fitness<0 & fitness_w_disp>=0)))
        
        base_prod<-mean(rowSums(fitness0*(fitness0>0)))
        total_prod<-home_prod+disp_prod_ME
        
        home_prod_prop<-home_prod/total_prod
        SS_prod<-home_prod-base_prod
        SS_prod[SS_prod<0]<-0
        if(mean(rowSums(N>0))<=1){SS_prod<-0}
        SS<-(SS_prod/home_prod)*home_prod_prop
        SS[is.nan(SS)]<-0
        if(total_prod==0){SS<-NA}
        Meta_dyn$Species_sorting[sampleValue]<-SS
        
        ME<-(disp_prod_ME)/total_prod
        ME[is.nan(ME)]<-0
        if(total_prod==0){ME<-NA}
        Meta_dyn$Mass_effects[sampleValue]<-ME
        
        BP<-home_prod_prop*(1-(SS_prod/home_prod))
        BP[is.nan(BP)]<-0
        if(total_prod==0){BP<-NA}
        Meta_dyn$Base_growth[sampleValue]<-BP
        
        Species_data[sampleValue,,1]<-colSums(N)
        Species_data[sampleValue,,2]<-colSums(N>0)
      }
      N <- Nt * (Nt>Ext) # set to 0 if below extinction threshold
      R <- Rt
      
      N0 <- Nt0 * (Nt0>Ext) # set to 0 if below extinction threshold
      R0 <- Rt0
    } 
    
    Abund<-array(t(Abund),dim=c(length(sampleV),species,numCom))
    
    hold_data<-data.frame(L_SR=mean(apply(Abund>0,3,rowSums)),
                          R_SR=mean(rowSums(apply(Abund,2,rowSums)>0)), 
                          L_Biomass= mean(apply(Abund,3,rowSums)),
                          Base_growth=mean(Meta_dyn$Base_growth,na.rm=T),
                          Species_sorting=mean(Meta_dyn$Species_sorting,na.rm=T),
                          Mass_effects=mean(Meta_dyn$Mass_effects,na.rm=T),
                          Dispersal=dispersal)
    if(i==1){
      SIH_data<-hold_data
    } else {
      SIH_data<-rbind(SIH_data,hold_data)
    }
  }
  return(SIH_data)
}

vect<-c(0.0001,0.00015,0.00025,0.0005,0.00075)
dispV<-c(vect,vect*10,vect*100,vect*1000,1)
dispV<-dispV[-c(17:20)]

reps<-100

#make parallel####
cl<-makeCluster(detectCores())
registerDoParallel(cl)
getDoParWorkers()

Sim_data_parallel<-foreach(r = 1:reps,.packages=c("igraph","dplyr","tidyr")) %dopar% SIH_function(species = 10,numCom = 100, dispV=dispV)
stopCluster(cl)

Sim_data<-do.call("rbind",Sim_data_parallel)

Sim_data_long<-gather(Sim_data,key = Response,value = Value,L_SR:Mass_effects)

SIH_means<-Sim_data_long%>%
  group_by(Dispersal,Response)%>%
  summarise_each(funs(Mean=mean(.,na.rm=T),Lower=quantile(.,probs = 0.25,na.rm=T),Upper=quantile(.,probs=0.75,na.rm=T)))

Meta.dyn.df<-filter(SIH_means,Response=="Base_growth" |
                      Response == "Species_sorting" |
                      Response == "Mass_effects")

Meta.dyn.df$Response<-factor(Meta.dyn.df$Response,levels =c("Base_growth","Species_sorting", "Mass_effects"),ordered = T)

save(Meta.dyn.df,file="Meta_dynamics.RData")



